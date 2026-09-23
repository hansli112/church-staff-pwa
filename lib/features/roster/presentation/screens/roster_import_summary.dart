import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';

import 'package:church_staff_pwa/core/types/service_type.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../../core/utils/error_messages.dart';
import '../../domain/roster_import.dart';

/// 一切順利時的 snackbar 文字。
///
/// 只有 [RosterImportSummary.hasIssues] 為 false 時才會用到 —— 有任何未匹配
/// 都改開匯入結果視窗，因為那裡才有補設定的按鈕。
///
/// 外來講員不算問題、不會開匯入結果視窗，但名字要讓人看得到 —— 不然
/// 「講員有沒有排上去」只能自己去翻服事表。
String importResultMessage(RosterImportSummary summary) {
  if (summary.updated == 0) return '找不到可更新的日期';
  final guests = summary.guestSpeakerNames;
  return [
    '已更新 ${summary.updated} 筆服事表',
    if (guests.isNotEmpty) '外來講員：${guests.join('、')}',
  ].join('。');
}

/// 補設定失敗、而且原因是使用者看得懂也能處理的。
///
/// 一般例外會經過 mapErrorToUserMessage 變成「操作失敗，請稍後再試」——
/// 對「有兩位同工都叫王大明」這種訊息來說那等於把唯一有用的資訊丟掉，使用者
/// 只會一直按重試。這類原因用這個型別丟出來，原文直接顯示。
class ImportFixException implements Exception {
  const ImportFixException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 把某個服事加進某個人的服事設定。失敗時丟例外，由呼叫端顯示訊息。
typedef AddMinistryToUser =
    Future<void> Function(String userName, List<String> roles);

/// 把一個活動加進這個崇拜的活動清單（顏色自動挑）。失敗時丟例外。
typedef AddEventOption = Future<void> Function(String eventName);

/// 依姓名把服事加進該同工在 [type] 這個崇拜的服事設定。
///
/// 抽成純函式是為了能單獨測 —— 補設定不能覆蓋掉他既有的服事，也不能把他在
/// 別的崇拜的設定弄掉，這兩件事出錯都要等到下次排班才會發現。
User addMinistriesToUser(User user, ServiceType type, List<String> roles) {
  final zones = List<UserZoneInfo>.from(user.zones);
  final index = zones.indexWhere((zone) => zone.serviceType == type);

  if (index < 0) {
    // 這個人在這個崇拜還沒有任何設定，開一筆新的。
    return user.copyWith(
      zones: [
        ...zones,
        UserZoneInfo(serviceType: type, ministries: [...roles]),
      ],
    );
  }

  // 保留既有順序，只把還沒有的接在後面。
  final merged = List<String>.from(zones[index].ministries);
  for (final role in roles) {
    if (!merged.contains(role)) merged.add(role);
  }
  zones[index] = zones[index].copyWith(ministries: merged);
  return user.copyWith(zones: zones);
}

// ── Dialog ──────────────────────────────────────────────────────────────────

class RosterImportSummaryDialog extends StatefulWidget {
  const RosterImportSummaryDialog({
    super.key,
    required this.summary,
    required this.type,
    required this.onAddMinistry,
    this.onAddEvent,
  });

  final RosterImportSummary summary;
  final ServiceType type;

  /// null 表示這個人沒有改別人設定的權限（補設定寫的是 `users/{uid}`，那是
  /// admin only）。服事表編輯者進得來這個匯入流程，但補不了設定 —— 與其給他
  /// 一顆按下去必定失敗的按鈕，不如不要給，並且說清楚要找誰。
  final AddMinistryToUser? onAddMinistry;

  /// null 表示不能改活動清單（`settings/` 是 admin only），理由同上。
  final AddEventOption? onAddEvent;

  @override
  State<RosterImportSummaryDialog> createState() =>
      _RosterImportSummaryDialogState();
}

enum _ActionState { idle, running, done, failed }

/// 匯入結果上可以按的是哪一種補救。
enum _ActionKind { addMinistry, addEvent }

/// 一列的身分。同一個人有多個服事，狀態要能分開記，所以 key 不能只用姓名；
/// 活動跟人分開記，活動名稱剛好跟某個人名一樣也不會連動。用 record 而不是
/// 把幾段字串接起來：接起來就得挑一個不會出現在名字裡的分隔符。
typedef _RowKey = ({_ActionKind kind, String name, String? role});

/// 單筆補設定的等待上限。公開出來讓測試不必真的等。
const Duration fixTimeout = Duration(seconds: 20);

class _RosterImportSummaryDialogState extends State<RosterImportSummaryDialog> {
  final Map<_RowKey, _ActionState> _actionStates = {};
  final Map<_RowKey, String> _actionErrors = {};

  /// 一次只跑一筆。每筆新增都是「讀出這個人 → 加一項 → 整份寫回」，同一個人
  /// 的兩個服事若同時送出，兩邊都會讀到修改前的資料，後寫的那筆會把先寫的
  /// 蓋掉 —— 使用者會看到兩行都變成已新增，實際上只進去一項。
  ///
  /// 這條鏈永遠不會 reject（失敗在各自的 try 裡收掉），所以一筆失敗不會把
  /// 後面排隊的一起卡死。
  Future<void> _queue = Future<void>.value();

  static _RowKey _ministryKey(String name, String role) =>
      (kind: _ActionKind.addMinistry, name: name, role: role);

  static _RowKey _eventKey(String name) =>
      (kind: _ActionKind.addEvent, name: name, role: null);

  Future<void> _fix(String name, String role) async {
    final onAddMinistry = widget.onAddMinistry;
    // 沒有權限時按鈕根本不會渲染，走到這裡代表呼叫端搞錯了 —— 靜靜地什麼都
    // 不做比拋 null 例外好，這是對話框不是後端。
    if (onAddMinistry == null) return;
    await _runQueued(
      _ministryKey(name, role),
      () => onAddMinistry(name, [role]),
    );
  }

  Future<void> _addEvent(String name) async {
    final onAddEvent = widget.onAddEvent;
    if (onAddEvent == null) return;
    await _runQueued(_eventKey(name), () => onAddEvent(name));
  }

  /// 排進 [_queue] 跑一筆寫入，並把狀態記在 [key] 那一列。
  ///
  /// 活動也走同一條隊伍，理由跟補設定一樣：活動清單是整份文件寫回去的，
  /// 兩個活動同時加，後寫的那筆會把先加的蓋掉。
  Future<void> _runQueued(_RowKey key, Future<void> Function() write) async {
    setState(() {
      _actionStates[key] = _ActionState.running;
      _actionErrors.remove(key);
    });

    final previous = _queue;
    final done = Completer<void>();
    _queue = done.future;
    try {
      await previous;
      // 逾時是這條鏈的活命條件，不只是體貼。這是 PWA，斷線時 Firestore 的
      // 寫入 future 不會 resolve —— 沒有逾時的話 done 永遠不 complete，之後
      // 每一列都會卡在 await previous 上無限轉圈，連錯誤訊息都沒有。
      //
      // 逾時不會取消已經送出的寫入，但兩種寫入都是冪等的（補設定不會重複加，
      // 同名活動已經在清單裡就不再寫），重試安全。
      await write().timeout(fixTimeout);
      if (mounted) setState(() => _actionStates[key] = _ActionState.done);
    } catch (e, st) {
      log('匯入結果補設定失敗', error: e, stackTrace: st);
      if (mounted) {
        setState(() {
          _actionStates[key] = _ActionState.failed;
          _actionErrors[key] = e is ImportFixException
              ? e.message
              : mapErrorToUserMessage(e);
        });
      }
    } finally {
      done.complete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('匯入結果'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '已更新 ${summary.updated} 筆服事表',
                style: theme.textTheme.bodyMedium,
              ),
              // 只講事實，不派工作。這些人多半是臨時來支援的，一年可能就這麼
              // 一次 —— 把他們永久設成該服事的固定班底反而會弄髒名單。要不要
              // 補設定是管理者當下才知道的判斷，畫面不該替他決定。
              if (summary.canPromiseAllImported)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '下面的名字都已經排進表裡了。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),

              if (summary.roleMismatchDetails.isNotEmpty)
                _Section(
                  title: '沒有設定這個服事',
                  note: widget.onAddMinistry == null ? '只有管理員能補進他的服事設定。' : null,
                  // 一個服事一列。同一個人被排到兩項時，可能只有其中一項該
                  // 補進設定（另一項是臨時支援），綁在一起就只能全補或全不補。
                  children: [
                    for (final entry in summary.roleMismatchDetails.entries)
                      if (entry.value.isEmpty)
                        // 沒有具體服事可補時仍然要列出來，不能讓這個人從
                        // 報告上消失。沒有服事就沒有東西可補，所以不給按鈕
                        // —— 按了也只是把同一份資料再寫一次。
                        _ActionRow(text: entry.key)
                      else
                        for (final role in entry.value)
                          _ActionRow(
                            text: '${entry.key}：$role',
                            state:
                                _actionStates[_ministryKey(entry.key, role)] ??
                                _ActionState.idle,
                            error: _actionErrors[_ministryKey(entry.key, role)],
                            action: widget.onAddMinistry == null
                                ? null
                                : _RowAction(
                                    label: '新增服事至同工',
                                    doneLabel: '已新增',
                                    onPressed: () => _fix(entry.key, role),
                                  ),
                          ),
                  ],
                ),

              if (summary.notInRosterNames.isNotEmpty)
                _Section(
                  title: '名單裡沒有這個人',
                  note: '他收不到服事提醒。',
                  children: [
                    for (final name in summary.notInRosterNames)
                      // 名單裡有很像的就一起列出來。名字是照表上原文寫進去
                      // 的，沒有自動換成候選那位 —— 還沒建帳號的新同工，
                      // 名字常常跟某個真人只差一個字，自動換等於把他的服事
                      // 記到別人頭上。要不要改是管理者看了才知道。
                      _PlainRow(
                        text: switch (summary.nearMatchSuggestions[name]) {
                          null => name,
                          final similar when similar.isEmpty => name,
                          final similar =>
                            '$name（名單裡有很像的：${similar.join('、')}）',
                        },
                      ),
                  ],
                ),

              // 講員沒有帳號是常態，所以不用「名單裡沒有這個人」那種口氣，
              // 也不拆成一人一行 —— 一行帶過，知道名字有寫進去就好。
              if (summary.guestSpeakerNames.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    '外來講員：${summary.guestSpeakerNames.join('、')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),

              if (summary.otherNames.isNotEmpty)
                _Section(
                  title: '不確定是哪一位',
                  // 這一格沒有連到任何帳號 —— 名字照樣寫上去了，但兩位都不會
                  // 在自己的首頁看到，也收不到提醒。不講清楚的話，管理者只會
                  // 覺得「反正名字有出現」就過去了。
                  note: '這一格沒有對到帳號，兩位都收不到服事提醒。',
                  children: [
                    for (final name in summary.otherNames)
                      _PlainRow(text: name),
                  ],
                ),

              if (summary.missingDates.isNotEmpty)
                _Section(
                  title: '這幾天沒有匯入',
                  note: '服事表裡找不到這些日期。',
                  children: [
                    for (final date in summary.missingDates)
                      _PlainRow(text: date),
                  ],
                ),

              if (summary.notInEventCatalog.isNotEmpty)
                _Section(
                  title: '活動沒有固定顏色',
                  note: widget.onAddEvent == null
                      ? '只有管理員能加進活動清單。'
                      // 講清楚按下去會發生什麼：顏色是挑的，不是問的。
                      : '加進活動清單後會自動配一個顏色，之後可以在活動設定改。',
                  children: [
                    for (final name in summary.notInEventCatalog)
                      _ActionRow(
                        text: name,
                        state:
                            _actionStates[_eventKey(name)] ?? _ActionState.idle,
                        error: _actionErrors[_eventKey(name)],
                        action: widget.onAddEvent == null
                            ? null
                            : _RowAction(
                                label: '加入活動清單',
                                doneLabel: '已加入',
                                onPressed: () => _addEvent(name),
                              ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('關閉'),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.note, required this.children});

  final String title;

  /// 標題已經講清楚時就不要再補一句 —— 使用者是同工不是工程師，每多一行
  /// 都是一行要讀的東西。
  final String? note;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 2),
            Text(
              note!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }
}

class _PlainRow extends StatelessWidget {
  const _PlainRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SelectableText('・$text', style: const TextStyle(fontSize: 13)),
    );
  }
}

/// 一列右邊那顆「補上」的按鈕：按鈕上的字、做完之後換成的字、按下去做什麼。
/// 三個一定一起出現，所以包在一起，而不是三個各自可以是 null 的參數。
class _RowAction {
  const _RowAction({
    required this.label,
    required this.doneLabel,
    required this.onPressed,
  });

  final String label;

  /// 做完之後那個位置顯示的字。同一行左邊已經寫著是誰、哪一項，所以短短
  /// 一個「已新增」就夠。
  final String doneLabel;

  final VoidCallback onPressed;
}

/// 一列文字，右邊可能帶一顆「補上」的按鈕，按下去之後換成狀態。
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.text,
    this.state = _ActionState.idle,
    this.error,
    this.action,
  });

  final String text;
  final _ActionState state;
  final String? error;

  /// null 代表補不了：不是沒有東西可補，就是這個人沒有權限。兩種情況都只列
  /// 出文字，不給按鈕 —— 給一顆按下去必定失敗的按鈕，使用者只會一直重試，
  /// 而錯誤訊息是泛用的「操作失敗，請稍後再試」。
  final _RowAction? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = this.action;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('・$text', style: const TextStyle(fontSize: 13)),
              ),
              if (action != null) ...[
                const SizedBox(width: 8),
                switch (state) {
                  _ActionState.running => const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  _ActionState.done => Text(
                    action.doneLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  _ActionState.idle || _ActionState.failed => TextButton(
                    onPressed: action.onPressed,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(
                      state == _ActionState.failed ? '重試' : action.label,
                    ),
                  ),
                },
              ],
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Text(
                error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
