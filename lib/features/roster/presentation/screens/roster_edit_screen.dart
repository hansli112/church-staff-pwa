import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/service_roster.dart';
import 'package:church_staff_pwa/core/types/service_type.dart';
import '../../../auth/presentation/providers/session_provider.dart';
import '../../../auth/presentation/providers/user_admin_provider.dart';
import '../../../auth/domain/entities/user.dart';
import '../../data/roster_import_service.dart';
import '../../data/roster_photo.dart';
import '../../data/roster_photo_picker.dart';
import '../providers/roster_provider.dart';
import '../widgets/roster_card.dart';
import '../../../../core/utils/error_messages.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/utils/scroll_anchor.dart';
import '../../../../core/utils/snappy_page_scroll_physics.dart';
import '../../../../core/widgets/settings_bottom_sheet.dart';
import 'event_settings_screen.dart' deferred as event_settings_screen;
import 'role_settings_screen.dart' deferred as role_settings_screen;
import '../../domain/roster_import.dart';
import 'roster_import_summary.dart';

class RosterEditScreen extends StatefulWidget {
  final VoidCallback onExit;
  final TabController? tabController;
  final List<ServiceType> allowedTypes;

  const RosterEditScreen({
    super.key,
    required this.onExit,
    required this.tabController,
    required this.allowedTypes,
  });

  @override
  State<RosterEditScreen> createState() => _RosterEditScreenState();
}

class _RosterEditScreenState extends State<RosterEditScreen> {
  Future<void> _loadAndPush(
    BuildContext context,
    Future<void> Function() loadLibrary,
    Widget Function() builder,
  ) async {
    var dialogShown = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await loadLibrary();
      if (!context.mounted) return;
      if (dialogShown) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogShown = false;
      }
      Navigator.push(context, MaterialPageRoute(builder: (_) => builder()));
    } catch (error, st) {
      log('載入設定畫面失敗', error: error, stackTrace: st);
      if (context.mounted) {
        if (dialogShown) {
          Navigator.of(context, rootNavigator: true).pop();
          dialogShown = false;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('載入失敗：${mapErrorToUserMessage(error)}')),
        );
      }
    } finally {
      if (dialogShown && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final session = context.read<SessionProvider>();

      if (!session.canEditRoster) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('沒有權限進入編輯模式')));
        widget.onExit();
        return;
      }

      // 進入編輯模式時，背景補齊本季 + 下季的 roster（backfill）。
      // 在無編輯權的路徑下已 return，此處一定有寫入權 —— 但只在自己的牧區內，
      // 所以補的範圍限制在 allowedTypes（同一個 batch 混進別的聚會別會整批被
      // rules 拒絕）。失敗靜默處理（ensureQuarterRosters 內部 catch），不影響 UI。
      context.read<RosterProvider>().ensureQuarterRostersForEditor(
        widget.allowedTypes,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final allowedTypes = widget.allowedTypes;
    // settings 的寫入權在 firestore.rules 裡是 admin only，所以非 admin 看到
    // 這兩顆按鈕只會按下去然後失敗 —— 不如不要顯示。
    final isAdmin = context.select<SessionProvider, bool>((s) => s.isAdmin);
    final now = DateTime.now();
    final quarterStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
    final isLastMonthOfQuarter = now.month == (quarterStartMonth + 2);
    final titleText = isLastMonthOfQuarter ? '編輯本季/下季服事表' : '編輯本季服事表';

    final appBar = AppBar(
      title: Text(titleText),
      centerTitle: true,
      actions: [
        if (isAdmin) ...[
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            tooltip: '事件選項設定',
            onPressed: () => _loadAndPush(
              context,
              event_settings_screen.loadLibrary,
              () => event_settings_screen.EventSettingsScreen(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.list_alt_outlined),
            tooltip: '服事項目設定',
            onPressed: () => _loadAndPush(
              context,
              role_settings_screen.loadLibrary,
              () => role_settings_screen.RoleSettingsScreen(),
            ),
          ),
        ],
        IconButton(
          icon: const Icon(Icons.view_list),
          tooltip: '切換至檢視模式',
          onPressed: widget.onExit,
        ),
      ],
      bottom: allowedTypes.isEmpty
          ? null
          : TabBar(
              controller: widget.tabController,
              tabs: allowedTypes.map((type) => Tab(text: type.label)).toList(),
              indicatorSize: TabBarIndicatorSize.label,
              // 讓切換時的動畫更平滑
              splashFactory: NoSplash.splashFactory,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            ),
    );

    if (allowedTypes.isEmpty) {
      return Scaffold(
        appBar: appBar,
        body: const EmptyState(
          icon: Icons.folder_off_outlined,
          message: '尚未設定可檢視的牧區',
          hint: '請先到使用者管理為您指派服事牧區',
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      // 同 roster_screen：不要用 Consumer 包住整個 body，否則每次
      // notifyListeners 都會重建整棵 TabBarView 與所有卡片。
      body: Builder(
        builder: (context) {
          // stale-while-revalidate: only block the UI with a spinner when
          // there is truly no data to show yet.  If we already have cached
          // rosters the TabBarView renders immediately while the background
          // server fetch runs silently.
          final showSpinner = context.select<RosterProvider, bool>(
            (provider) => provider.isLoading && provider.rosters.isEmpty,
          );
          if (showSpinner) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    '載入服事資訊中…',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            );
          }

          final error = context.select<RosterProvider, String?>(
            (provider) => provider.error,
          );
          if (error != null) {
            return EmptyState(
              icon: Icons.error_outline,
              message: error,
              action: FilledButton.icon(
                onPressed: () =>
                    context.read<RosterProvider>().fetchInitialData(),
                icon: const Icon(Icons.refresh),
                label: const Text('重試'),
              ),
            );
          }

          // TabBarView 預設支援左右滑動
          return TabBarView(
            // 收尾動畫越久，「換完分頁馬上想往下滑卻沒反應」的窗口就越長。
            physics: const SnappyPageScrollPhysics(),
            controller: widget.tabController,
            children: allowedTypes.map((type) {
              return _RosterList(
                key: PageStorageKey(type.toString()),
                type: type,
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _RosterList extends StatefulWidget {
  final ServiceType type;

  const _RosterList({super.key, required this.type});

  @override
  State<_RosterList> createState() => _RosterListState();
}

// 使用 AutomaticKeepAliveClientMixin 來保持滑動位置
class _RosterListState extends State<_RosterList>
    with AutomaticKeepAliveClientMixin, ScrollAnchorSupport {
  @override
  bool get wantKeepAlive => true; // 告訴 Flutter 保持這個頁面的狀態

  // dispose 期間 context 已經查不到 InheritedWidget，所以進場時就把 provider
  // 抓在手上，撤銷登記時才有東西可用。
  late final RosterProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = context.read<RosterProvider>();
    _provider.registerScrollAnchorCapture(widget.type, captureScrollAnchor);
    // 檢視模式切進來時，把當初頂端那一天挪回原本的位置：編輯清單多了一張匯入
    // 卡、每列多了兩顆按鈕，同一個 pixel offset 在這裡指到的是別天。
    final anchor = _provider.scrollAnchorFor(widget.type);
    if (anchor != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => restoreScrollAnchor(anchor),
      );
    }
  }

  @override
  void dispose() {
    _provider.unregisterScrollAnchorCapture(widget.type, captureScrollAnchor);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必須呼叫 super.build
    final isEditMode = context.select<RosterProvider, bool>(
      (provider) => provider.isEditMode,
    );
    // 只訂閱這個牧區的清單（getRostersByType 有快取，資料沒變時 identity 不變）。
    final rosters = context.select<RosterProvider, List<ServiceRoster>>(
      (provider) => provider.getRostersByType(widget.type),
    );

    if (rosters.isEmpty) {
      return EmptyState(
        icon: Icons.event_busy_outlined,
        message: '此類別目前沒有服事資訊',
        hint: isEditMode
            ? (canPickRosterPhotos ? '可以用服事表照片快速建立' : '可貼上 JSON 快速建立')
            : '管理員建立後會在這裡顯示',
        action: isEditMode
            ? OutlinedButton.icon(
                onPressed: () => _showImportJsonDialog(context),
                icon: const Icon(Icons.upload_file),
                label: const Text('匯入服事表'),
              )
            : null,
      );
    }

    final showImport = isEditMode;
    return ListView.builder(
      key: anchorListKey,
      controller: anchorController,
      padding: const EdgeInsets.only(top: 12, bottom: 20),
      itemCount: rosters.length + (showImport ? 1 : 0),
      itemBuilder: (context, index) {
        if (showImport && index == 0) {
          return _buildImportCard(context);
        }
        final rosterIndex = index - (showImport ? 1 : 0);
        final roster = rosters[rosterIndex];
        return ScrollAnchorItem(
          key: ValueKey(roster.id),
          id: roster.id,
          child: RosterCard(
            roster: roster,
            initiallyExpanded: rosterIndex == 0,
          ),
        );
      },
    );
  }

  Widget _buildImportCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('匯入服事表', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    canPickRosterPhotos
                        ? '用服事表照片辨識，依日期批次填入'
                        : '貼上陣列格式，依日期批次填入服事表',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: () => _showImportJsonDialog(context),
              icon: const Icon(Icons.upload_file),
              label: const Text('匯入'),
            ),
          ],
        ),
      ),
    );
  }

  /// 照片轉 JSON。建一次就好 —— 它沒有狀態，每次開 sheet 都新建一個
  /// http.Client 只是多開連線池。
  late final RosterImportService _importService = RosterImportService();

  Future<void> _showImportJsonDialog(BuildContext context) async {
    final result = await showModalBottomSheet<_JsonImportResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => _ImportJsonSheet(
        type: widget.type,
        importService: _importService,
        onSubmit: (raw) => _applyJsonImport(sheetContext, raw),
      ),
    );
    // sheet 自己關掉時才有結果。成功之後的報告留在這裡而不是 sheet 裡：
    // 匯入結果視窗要活得比 sheet 久，掛在正在退場的那棵子樹上會被一起帶走。
    if (result == null || !context.mounted) return;

    final summary = result.summary;
    if (summary == null) return;
    if (summary.hasIssues) {
      await _showImportSummaryDialog(context, summary);
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(importResultMessage(summary))));
  }

  /// 依姓名把服事補進該同工的設定。
  ///
  /// 失敗一律丟 [ImportFixException]：這幾種原因使用者看得懂也處理得了，被
  /// mapErrorToUserMessage 壓成「操作失敗，請稍後再試」的話就只剩重試可按。
  Future<void> _addMinistryToUser(
    UserAdminProvider userAdminProvider,
    List<String> templateRoles,
    String name,
    List<String> roles,
  ) async {
    // 樣板裡沒有的服事寫進去也留不住：帳號管理的選單只渲染樣板內的項目，
    // 看不到也刪不掉，而下次有人存檔服事項目設定時 cleanupUserMinistries 會
    // 把它清掉 —— 使用者只會看到自己按過「已新增」的東西過陣子又被報一次。
    // 與其讓它悄悄消失，不如當場說清楚。
    final outside = roles.where((r) => !templateRoles.contains(r)).toList();
    if (outside.isNotEmpty) {
      throw ImportFixException(
        '「${outside.join('、')}」不在服事項目樣板裡，加了也會被清掉。'
        '請先到服事項目設定新增這個項目',
      );
    }

    final users = await userAdminProvider.getUsers();
    final matches = users.where((u) => u.name.trim() == name.trim()).toList();
    if (matches.isEmpty) {
      throw ImportFixException('找不到同工「$name」，可能已被刪除');
    }
    // 同名同姓時刻意不猜：補錯人的設定沒有任何跡象，會一路錯到下次排班。
    if (matches.length > 1) {
      throw ImportFixException('有 ${matches.length} 位同工都叫「$name」，請到帳號管理手動設定');
    }
    await userAdminProvider.updateUser(
      addMinistriesToUser(matches.single, widget.type, roles),
    );
  }

  Future<void> _showImportSummaryDialog(
    BuildContext context,
    RosterImportSummary summary,
  ) async {
    final userAdminProvider = context.read<UserAdminProvider>();
    // 補設定寫的是 users/{uid}、加活動寫的是 settings/，firestore.rules 裡
    // 兩個都是 admin only。服事表編輯者進得來匯入流程，但這兩項都補不了。
    final isAdmin = context.read<SessionProvider>().isAdmin;
    final rosterProvider = context.read<RosterProvider>();
    final templateRoles = rosterProvider.templates[widget.type] ?? const [];
    await showDialog(
      context: context,
      builder: (context) {
        return RosterImportSummaryDialog(
          type: widget.type,
          summary: summary,
          onAddMinistry: isAdmin
              ? (name, roles) => _addMinistryToUser(
                  userAdminProvider,
                  templateRoles,
                  name,
                  roles,
                )
              : null,
          onAddEvent: isAdmin
              ? (name) => rosterProvider.addEventOption(widget.type, name)
              : null,
        );
      },
    );
  }

  /// 讀現況、交給 [planRosterImport]、把它要寫的寫進去。
  ///
  /// 怎麼對名字、怎麼排順序、哪天要改什麼都在 planRosterImport 裡，這裡只剩
  /// 它碰不到的兩件事：讀同工名單、寫 Firestore。
  Future<_JsonImportResult> _applyJsonImport(
    BuildContext context,
    String raw,
  ) async {
    final userAdminProvider = context.read<UserAdminProvider>();
    final rosterProvider = context.read<RosterProvider>();

    final List<User> users;
    try {
      users = await userAdminProvider.getUsers();
    } catch (_) {
      return const _JsonImportResult.failed('無法載入同工名單');
    }

    final plan = planRosterImport(
      input: raw,
      type: widget.type,
      users: users,
      rosters: rosterProvider.getRostersByType(widget.type),
      templates: rosterProvider.templatesLoaded
          ? rosterProvider.templates
          : null,
      eventOptions: rosterProvider.eventOptionsFor(widget.type),
    );
    final RosterImportReady ready;
    switch (plan) {
      case RosterImportRejected(:final message):
        return _JsonImportResult.failed(message);
      case RosterImportReady():
        ready = plan;
    }

    try {
      await rosterProvider.updateRosters(ready.updates);
    } catch (e, st) {
      log('匯入過程寫入 Firestore 失敗', error: e, stackTrace: st);
      String msg;
      if (e is PartialUpdateException) {
        // Log the underlying cause's stack too so future Sentry has the
        // real Firestore error, not just the wrapping exception's stack.
        log('匯入部分失敗的代表性 cause', error: e.cause, stackTrace: e.causeStackTrace);
        final failedDates = e.failedRosters
            .map((r) => rosterDateKey(r.date))
            .join('、');
        msg =
            '${e.successCount} 筆已寫入、${e.failureCount} 筆失敗。'
            '失敗日期：$failedDates。請重新整理確認狀態後重試';
      } else {
        msg = mapErrorToUserMessage(e);
      }
      return _JsonImportResult.failed('匯入過程寫入失敗：$msg');
    }

    return _JsonImportResult.done(ready.summary);
  }
}

/// sheet 交回來的東西：寫完的報告，或是要留在 sheet 上的錯誤。
class _JsonImportResult {
  const _JsonImportResult.done(RosterImportSummary this.summary) : error = null;
  const _JsonImportResult.failed(String this.error) : summary = null;

  final RosterImportSummary? summary;
  final String? error;
}

/// 匯入用的 bottom sheet。
///
/// 抽成獨立的 widget 而不是留在 `_showImportJsonDialog` 裡的 StatefulBuilder：
/// 那個函式長到兩百行，而其中真正屬於畫面的狀態有四個（錯誤、送出中、辨識中、
/// JSON 欄位開合），全靠閉包變數撐著。有了 State 之後 controller 也能自己
/// dispose —— dispose 是在退場動畫結束後才跑的，不會像 sheet 的 future 那樣
/// 在 pop 當下就把 TextField 底下的東西抽掉。
class _ImportJsonSheet extends StatefulWidget {
  const _ImportJsonSheet({
    required this.type,
    required this.importService,
    required this.onSubmit,
  });

  final ServiceType type;
  final RosterImportService importService;

  /// 真正寫進 Firestore 的那一步。留在畫面外面是因為它要用到 provider 與
  /// 服事表樣板，那些是 screen 的事，不是這張 sheet 的。
  final Future<_JsonImportResult> Function(String raw) onSubmit;

  @override
  State<_ImportJsonSheet> createState() => _ImportJsonSheetState();
}

class _ImportJsonSheetState extends State<_ImportJsonSheet> {
  final TextEditingController _controller = TextEditingController();
  String? _errorText;
  bool _isSubmitting = false;
  bool _isConverting = false;

  /// 選照片的那段時間也要算「忙碌」。只在辨識開始後才鎖按鈕的話，iPhone 上
  /// 一次點擊偶爾會觸發兩次，第二個選擇器排在第一個後面，選完一張又跳出一個。
  /// 用欄位而不是 setState 判斷：第二次觸發跟第一次在同一個 frame 內，等不到
  /// 重建按鈕就已經進來了。
  bool _isPicking = false;

  /// 有照片辨識可用時，貼 JSON 是備援而不是主要動作 —— 預設收起來。
  /// 辨識完會自動展開，因為那時它變成「看一眼再匯入」的地方。
  bool _showJsonField = !canPickRosterPhotos;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _convertFromPhoto() async {
    if (_isPicking || _isConverting) return;
    _isPicking = true;
    setState(() => _errorText = null);
    final RosterPhoto? photo;
    try {
      photo = await pickRosterPhoto();
    } on RosterPhotoException catch (e) {
      if (mounted) setState(() => _errorText = e.message);
      return;
    } catch (e, st) {
      _reportUnexpected(e, st);
      return;
    } finally {
      _isPicking = false;
    }
    // 使用者按了取消。那不是錯誤，什麼都不做。
    if (photo == null || !mounted) return;

    setState(() => _isConverting = true);
    try {
      final json = await widget.importService.convert(
        type: widget.type,
        photos: [photo],
      );
      if (!mounted) return;
      _controller.text = json;
      setState(() {
        _isConverting = false;
        _showJsonField = true;
      });
    } on RosterImportException catch (e) {
      if (!mounted) return;
      setState(() {
        _isConverting = false;
        _errorText = e.message;
      });
    } catch (e, st) {
      _reportUnexpected(e, st);
    }
  }

  /// 預期外的失敗（讀檔、拿登入 token 之類）也要讓畫面有反應。只接自己
  /// 定義的例外的話，其他錯誤會被 async 吞掉 —— 使用者看到的就是「選完照片
  /// 什麼都沒有」，連轉圈都沒有。
  void _reportUnexpected(Object error, StackTrace stackTrace) {
    debugPrint('roster photo import failed: $error\n$stackTrace');
    if (!mounted) return;
    setState(() {
      _isConverting = false;
      _errorText = '辨識失敗：$error';
    });
  }

  Future<void> _submit() async {
    // 空白時 parser 只會說「請貼上 JSON 內容」，但這個畫面上根本沒有可以貼的
    // 地方（文字框收著）—— 要講得出下一步在哪。
    if (_controller.text.trim().isEmpty && canPickRosterPhotos) {
      setState(() {
        _errorText = '請先從照片辨識，或展開下面自己貼 JSON';
        _showJsonField = true;
      });
      return;
    }

    setState(() {
      _errorText = null;
      _isSubmitting = true;
    });
    final result = await widget.onSubmit(_controller.text);
    if (!mounted) return;
    if (result.error != null) {
      setState(() {
        _errorText = result.error;
        _isSubmitting = false;
      });
      return;
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final busy = _isSubmitting || _isConverting;
    return SettingsBottomSheet(
      title: '匯入服事表（${widget.type.label}）',
      submitLabel: '匯入',
      isSubmitting: _isSubmitting,
      onSubmit: busy ? null : _submit,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 辨識結果填回下面那個文字框，不直接匯入：看一眼再按匯入是這個流程
          // 唯一的把關，而按下匯入走的還是跟手動貼上完全一樣的那條路。
          if (canPickRosterPhotos) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: busy ? null : _convertFromPhoto,
                icon: _isConverting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_camera_outlined, size: 18),
                label: Text(_isConverting ? '辨識中…' : '從照片辨識'),
              ),
            ),
            const SizedBox(height: 4),
            // 收合的理由不是版面好看，是這條路平常用不到：Gemini 掛掉、額度
            // 用完、模型下架時，從別處轉好再貼進來是唯一還走得通的路，所以它
            // 要在，但不該擋在前面。
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : () => setState(() => _showJsonField = !_showJsonField),
                icon: Icon(
                  _showJsonField
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 18,
                ),
                label: const Text('自己貼 JSON'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
          if (_showJsonField)
            TextField(
              controller: _controller,
              maxLines: 12,
              decoration: InputDecoration(
                hintText:
                    '[\n  {\n    "date": "2026-01-04",\n    "duties": [\n      {"people": ["待定"], "role": "敬拜主領"}\n    ],\n    "events": ["聖餐", {"name": "受洗禮", "color": "#F39C12"}]\n  }\n]',
                hintStyle: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.35),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.redAccent),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _errorText!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            canPickRosterPhotos
                ? '可以直接選服事表照片辨識，或自己貼上 JSON。'
                      '格式需為陣列，每筆含 date，並至少含 duties 或 events'
                : '格式需為 JSON 陣列，每筆含 date，並至少含 duties 或 events',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
