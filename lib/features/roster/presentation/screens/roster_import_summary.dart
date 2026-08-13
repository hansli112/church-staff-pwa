import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';

import 'package:church_staff_pwa/core/types/service_type.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../../core/utils/error_messages.dart';

/// 匯入之後的結果報告。
///
/// 沒對到的名字**已經照樣寫進服事表了**，列在這裡是讓你知道，不是要你回去
/// 補打名字，也不是叫你去改設定 —— 臨時支援別的崇拜是常態，那些人一年可能
/// 就來這麼一次，把他們設成固定班底反而會弄髒名單。
///
/// 所以文案一律只陳述事實，不寫祈使句。「新增服事至同工」那顆按鈕是備著的，不是
/// 建議的動作：真的多了一位固定班底時按一下省得跑一趟帳號管理，其餘時候
/// 放著就好。
class RosterImportSummary {
  const RosterImportSummary({
    required this.updated,
    required this.missingDates,
    required this.notInRosterNames,
    required this.roleMismatchDetails,
    required this.otherNames,
    required this.notInEventCatalog,
  });

  final int updated;
  final List<String> missingDates;
  final List<String> notInRosterNames;

  /// 人名 → 他被排到、但設定裡沒有的服事。
  final Map<String, List<String>> roleMismatchDetails;

  final List<String> otherNames;
  final List<String> notInEventCatalog;

  bool get hasIssues =>
      hasUnmatchedNames ||
      missingDates.isNotEmpty ||
      notInEventCatalog.isNotEmpty;

  /// 有沒有「人」沒對到。日期與活動不算 —— 那兩類跟「這些人已經排進去了」
  /// 那句安撫無關，不該一起把那句話帶出來。
  bool get hasUnmatchedNames =>
      notInRosterNames.isNotEmpty ||
      roleMismatchDetails.isNotEmpty ||
      otherNames.isNotEmpty;

  /// 能不能講「下面的名字都已經排進表裡了」。
  ///
  /// 未匹配的名單是整份 JSON 的統計，但日期找不到的那幾筆根本沒寫進去 ——
  /// 那些人名照樣會出現在清單上。只要有任何一天沒匯入，這句話就可能是假的；
  /// 一筆都沒更新時更是徹底的謊話。寧可不講，也不要讓管理者以為排好了。
  bool get canPromiseAllImported =>
      hasUnmatchedNames && updated > 0 && missingDates.isEmpty;
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
  });

  final RosterImportSummary summary;
  final ServiceType type;
  final AddMinistryToUser onAddMinistry;

  @override
  State<RosterImportSummaryDialog> createState() =>
      _RosterImportSummaryDialogState();
}

enum _FixState { idle, running, done, failed }

/// 單筆補設定的等待上限。公開出來讓測試不必真的等。
const Duration fixTimeout = Duration(seconds: 20);

class _RosterImportSummaryDialogState extends State<RosterImportSummaryDialog> {
  final Map<String, _FixState> _fixStates = {};
  final Map<String, String> _fixErrors = {};

  /// 一次只跑一筆。每筆新增都是「讀出這個人 → 加一項 → 整份寫回」，同一個人
  /// 的兩個服事若同時送出，兩邊都會讀到修改前的資料，後寫的那筆會把先寫的
  /// 蓋掉 —— 使用者會看到兩行都變成已新增，實際上只進去一項。
  ///
  /// 這條鏈永遠不會 reject（失敗在各自的 try 裡收掉），所以一筆失敗不會把
  /// 後面排隊的一起卡死。
  Future<void> _queue = Future<void>.value();

  /// 同一個人有多個服事，狀態要能分開記，key 不能只用姓名。
  ///
  /// 分隔符用跳脫寫法的 NUL 而不是空格：姓名或服事名裡若含空格，
  /// 「甲 乙」+「丙」會跟「甲」+「乙 丙」撞成同一個 key，兩列狀態就連動。
  /// 寫成跳脫序列而不是把控制字元直接打進原始碼 —— 原始碼裡真的塞一個
  /// NUL 會讓 file 判定成 binary，grep 從此靜靜地什麼都找不到。
  static String _rowKey(String name, String role) => '$name\u0000$role';

  Future<void> _fix(String name, String role) async {
    final key = _rowKey(name, role);
    setState(() {
      _fixStates[key] = _FixState.running;
      _fixErrors.remove(key);
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
      // 逾時不會取消已經送出的寫入，但補設定是冪等的（addMinistriesToUser
      // 不會重複加），重試安全。
      await widget.onAddMinistry(name, [role]).timeout(fixTimeout);
      if (mounted) setState(() => _fixStates[key] = _FixState.done);
    } catch (e, st) {
      log('新增服事至同工失敗', error: e, stackTrace: st);
      if (mounted) {
        setState(() {
          _fixStates[key] = _FixState.failed;
          _fixErrors[key] = e is ImportFixException
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
                  // 一個服事一列。同一個人被排到兩項時，可能只有其中一項該
                  // 補進設定（另一項是臨時支援），綁在一起就只能全補或全不補。
                  children: [
                    for (final entry in summary.roleMismatchDetails.entries)
                      if (entry.value.isEmpty)
                        // 沒有具體服事可補時仍然要列出來，不能讓這個人從
                        // 報告上消失。
                        _FixableRow(name: entry.key, state: _FixState.idle)
                      else
                        for (final role in entry.value)
                          _FixableRow(
                            name: entry.key,
                            role: role,
                            state:
                                _fixStates[_rowKey(entry.key, role)] ??
                                _FixState.idle,
                            error: _fixErrors[_rowKey(entry.key, role)],
                            onFix: () => _fix(entry.key, role),
                          ),
                  ],
                ),

              if (summary.notInRosterNames.isNotEmpty)
                _Section(
                  title: '名單裡沒有這個人',
                  note: '他收不到服事提醒。',
                  children: [
                    for (final name in summary.notInRosterNames)
                      _PlainRow(text: name),
                  ],
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
                  children: [
                    for (final name in summary.notInEventCatalog)
                      _PlainRow(text: name),
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

class _FixableRow extends StatelessWidget {
  const _FixableRow({
    required this.name,
    this.role,
    required this.state,
    this.error,
    this.onFix,
  });

  final String name;

  /// null 代表這筆沒有具體的服事可補（實務上碰不到）。仍然列出來，但不給
  /// 按鈕 —— 按了也只是把同一份資料再寫一次。
  final String? role;

  final _FixState state;
  final String? error;
  final VoidCallback? onFix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 一列只講一個人的一個服事，所以文字短，按鈕擺得下同一行。狀態文字用
    // 「已新增」就好 —— 同一行左邊已經寫著是誰、哪個服事。
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  role == null ? '・$name' : '・$name：$role',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (role != null) ...[
                const SizedBox(width: 8),
                switch (state) {
                  _FixState.running => const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  _FixState.done => Text(
                    '已新增',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  _FixState.idle || _FixState.failed => TextButton(
                    onPressed: onFix,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(state == _FixState.failed ? '重試' : '新增服事至同工'),
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
