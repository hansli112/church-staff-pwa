import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/service_roster.dart';
import 'package:church_staff_pwa/core/types/service_type.dart';
import '../../../auth/presentation/providers/session_provider.dart';
import '../../../auth/presentation/providers/user_admin_provider.dart';
import '../../../auth/domain/entities/user.dart';
import '../../domain/entities/event_option.dart';
import '../providers/roster_provider.dart';
import '../widgets/roster_card.dart';
import '../../../../core/utils/error_messages.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/utils/scroll_anchor.dart';
import '../../../../core/utils/snappy_page_scroll_physics.dart';
import '../../../../core/widgets/settings_bottom_sheet.dart';
import '../../../../core/widgets/text_controller_scope.dart';
import 'event_settings_screen.dart' deferred as event_settings_screen;
import 'role_settings_screen.dart' deferred as role_settings_screen;
import 'roster_import_parser.dart';
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
        hint: isEditMode ? '可使用 JSON 匯入快速建立' : '管理員建立後會在這裡顯示',
        action: isEditMode
            ? OutlinedButton.icon(
                onPressed: () => _showImportJsonDialog(context),
                icon: const Icon(Icons.data_object),
                label: const Text('JSON 匯入'),
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
                  Text(
                    'JSON 匯入',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '貼上陣列格式，依日期批次填入服事表',
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

  Future<void> _showImportJsonDialog(BuildContext context) async {
    // controller 由 TextControllerScope 在 bottom sheet 子樹卸載時 dispose ——
    // sheet 的 future 在 pop 當下就完成，那時 TextField 還在退場動畫中。
    final controller = TextEditingController();
    String? errorText;
    bool isSubmitting = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) {
        return TextControllerScope(
          controller: controller,
          child: StatefulBuilder(
            builder: (context, setState) {
              return SettingsBottomSheet(
                title: 'JSON 匯入（${widget.type.label}）',
                submitLabel: '匯入',
                isSubmitting: isSubmitting,
                onSubmit: isSubmitting
                    ? null
                    : () async {
                        setState(() {
                          errorText = null;
                          isSubmitting = true;
                        });
                        final result = await _applyJsonImport(
                          context,
                          controller.text,
                        );
                        if (!context.mounted) return;
                        if (result.error != null) {
                          setState(() {
                            errorText = result.error;
                            isSubmitting = false;
                          });
                          return;
                        }
                        Navigator.of(context).pop();
                        final summary = result.toSummary();
                        if (summary.hasIssues) {
                          if (!context.mounted) return;
                          await _showImportSummaryDialog(context, summary);
                        } else {
                          final message = _buildResultMessage(result);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(message)));
                        }
                      },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      maxLines: 12,
                      decoration: InputDecoration(
                        hintText:
                            '[\n  {\n    "date": "2026-01-04",\n    "duties": [\n      {"people": ["芳伶"], "role": "敬拜主領"}\n    ],\n    "events": ["聖餐", {"name": "受洗禮", "color": "#F39C12"}]\n  }\n]',
                        hintStyle: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.35),
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (errorText != null) ...[
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
                            errorText!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Text(
                      '格式需為 JSON 陣列，每筆含 date，並至少含 duties 或 events',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// 一切順利時的 snackbar 文字。
  ///
  /// 只有 `hasIssues` 為 false 時才會走到這裡 —— 有任何未匹配都改走匯入結果
  /// 視窗，因為那裡才有補設定的按鈕。
  String _buildResultMessage(_JsonImportResult result) {
    if (result.updated == 0) return '找不到可更新的日期';
    return '已更新 ${result.updated} 筆服事表';
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
    // 補設定寫的是 users/{uid}，firestore.rules 裡是 admin only。服事表編輯者
    // 進得來匯入流程，但這一項補不了。
    final canFixUsers = context.read<SessionProvider>().isAdmin;
    final templateRoles =
        context.read<RosterProvider>().templates[widget.type] ?? const [];
    await showDialog(
      context: context,
      builder: (context) {
        return RosterImportSummaryDialog(
          type: widget.type,
          summary: summary,
          onAddMinistry: canFixUsers
              ? (name, roles) => _addMinistryToUser(
                  userAdminProvider,
                  templateRoles,
                  name,
                  roles,
                )
              : null,
        );
      },
    );
  }

  Future<_JsonImportResult> _applyJsonImport(
    BuildContext context,
    String raw,
  ) async {
    final userAdminProvider = context.read<UserAdminProvider>();
    final rosterProvider = context.read<RosterProvider>();

    final List<String> candidateNames;
    final Map<String, Set<String>> allowedByRole;
    final Map<String, String> nameToIdMap;
    try {
      final users = await userAdminProvider.getUsers();
      candidateNames = [
        ...users.map((u) => u.name.trim()).where((name) => name.isNotEmpty),
      ];
      allowedByRole = _buildAllowedByRole(users);
      nameToIdMap = {
        for (final u in users)
          if (u.name.trim().isNotEmpty && u.id.trim().isNotEmpty)
            u.name.trim(): u.id.trim(),
      };
    } catch (_) {
      return const _JsonImportResult(error: '無法載入同工名單');
    }

    // Build catalog map for the current service type.
    final catalogByName = <String, EventOption>{
      for (final opt in rosterProvider.eventOptionsFor(widget.type))
        opt.name: opt,
    };

    final parsed = parseRosterImportJson(
      input: raw,
      candidateNames: candidateNames,
      allowedByRole: allowedByRole,
      catalogByName: catalogByName,
      nameToIdMap: nameToIdMap,
    );

    if (parsed.error != null) {
      return _JsonImportResult(error: parsed.error);
    }

    // 服事項目的順序完全由樣板決定，樣板不可靠就不能匯 —— 缺席時所有角色
    // 並列，會退回 JSON 的順序寫進 Firestore，畫面上看不出哪裡不對。
    //
    // 只擋含 duties 的匯入：只帶 events 的 JSON 根本不排序，沒有理由一起擋。
    //
    // `templatesLoaded` 不夠：updateTemplates 寫入空樣板之後旗標也是 true，
    // 但這個崇拜的鍵可能根本不存在。真正要問的是「這個崇拜的樣板拿得到嗎」。
    if (parsed.dutiesProvidedDates.isNotEmpty) {
      if (!rosterProvider.templatesLoaded) {
        return const _JsonImportResult(error: '服事項目樣板尚未載入，順序會排錯。請重新整理後再匯入');
      }
      if (!rosterProvider.templates.containsKey(widget.type)) {
        return _JsonImportResult(
          // 服事項目設定是 admin only，非 admin 連那顆按鈕都看不到，所以這裡
          // 講「請管理員」而不是「請先到」—— 後者對他是一條走不通的路。
          error: '${widget.type.label}還沒有服事項目樣板，順序會排錯。請管理員到服事項目設定新增',
        );
      }
    }

    // Collect all dates that appear in either duties or events.
    final allDates = <String>{
      ...parsed.dutiesProvidedDates,
      ...parsed.eventsProvidedDates,
    };

    final rosterByDate = <String, ServiceRoster>{
      for (final roster in rosterProvider.getRostersByType(widget.type))
        _dateKey(roster.date): roster,
    };
    final updates = <ServiceRoster>[];
    final missingDates = <String>[];

    final templateRoles = rosterProvider.templates[widget.type] ?? const [];

    for (final key in allDates) {
      final roster = rosterByDate[key];
      if (roster == null) {
        missingDates.add(key);
        continue;
      }

      final hasDuties = parsed.dutiesProvidedDates.contains(key);
      final hasEvents = parsed.eventsProvidedDates.contains(key);

      List<RosterEntry> newDuties = roster.duties;
      if (hasDuties) {
        newDuties = orderDutiesByTemplate(
          parsed.dutiesByDate[key] ?? const [],
          templateRoles,
        );
      }

      final newEvents = hasEvents
          ? (parsed.eventsByDate[key] ?? const <String>[])
          : roster.specialEvents;
      final newColors = hasEvents
          ? (parsed.colorsByDate[key] ?? const <String, int>{})
          : roster.customEventColors;

      updates.add(
        roster.copyWith(
          duties: newDuties,
          specialEvents: newEvents,
          customEventColors: newColors,
        ),
      );
    }

    // Normalize role-mismatch details (Set → sorted List).
    final normalizedMismatch = <String, List<String>>{};
    for (final entry in parsed.roleMismatchDetails.entries) {
      normalizedMismatch[entry.key] = entry.value.toList()..sort();
    }

    if (updates.isEmpty) {
      return _JsonImportResult(
        updated: 0,
        missingDates: missingDates,
        notInRosterNames: parsed.notInRosterNames,
        roleMismatchNames: parsed.roleMismatchNames,
        roleMismatchDetails: normalizedMismatch,
        otherNames: parsed.otherNames,
        notInEventCatalog: parsed.notInEventCatalog,
      );
    }

    try {
      await rosterProvider.updateRosters(updates);
    } catch (e, st) {
      log('匯入過程寫入 Firestore 失敗', error: e, stackTrace: st);
      String msg;
      if (e is PartialUpdateException) {
        // Log the underlying cause's stack too so future Sentry has the
        // real Firestore error, not just the wrapping exception's stack.
        log('匯入部分失敗的代表性 cause', error: e.cause, stackTrace: e.causeStackTrace);
        final failedDates = e.failedRosters
            .map((r) => _dateKey(r.date))
            .join('、');
        msg =
            '${e.successCount} 筆已寫入、${e.failureCount} 筆失敗。'
            '失敗日期：$failedDates。請重新整理確認狀態後重試';
      } else {
        msg = mapErrorToUserMessage(e);
      }
      return _JsonImportResult(error: '匯入過程寫入失敗：$msg');
    }

    return _JsonImportResult(
      updated: updates.length,
      missingDates: missingDates,
      notInRosterNames: parsed.notInRosterNames,
      roleMismatchNames: parsed.roleMismatchNames,
      roleMismatchDetails: normalizedMismatch,
      otherNames: parsed.otherNames,
      notInEventCatalog: parsed.notInEventCatalog,
    );
  }

  String _dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Map<String, Set<String>> _buildAllowedByRole(List<User> users) {
    final Map<String, Set<String>> allowed = {};
    for (final user in users) {
      final userName = user.name.trim();
      if (userName.isEmpty) continue;
      for (final zone in user.zones) {
        if (zone.serviceType != widget.type) continue;
        for (final ministry in zone.ministries) {
          final role = ministry.trim();
          if (role.isEmpty) continue;
          allowed.putIfAbsent(role, () => {});
          allowed[role]!.add(userName);
        }
      }
    }

    return allowed;
  }
}

class _JsonImportResult {
  final int updated;
  final List<String> missingDates;
  final List<String> notInRosterNames;
  final List<String> roleMismatchNames;
  final Map<String, List<String>> roleMismatchDetails;
  final List<String> otherNames;
  final List<String> notInEventCatalog;
  final String? error;

  const _JsonImportResult({
    this.updated = 0,
    this.missingDates = const [],
    this.notInRosterNames = const [],
    this.roleMismatchNames = const [],
    this.roleMismatchDetails = const {},
    this.otherNames = const [],
    this.notInEventCatalog = const [],
    this.error,
  });

  /// 轉成報告用的資料。
  ///
  /// roleMismatchDetails 刻意從 roleMismatchNames 反向長出來，而不是直接沿用：
  /// 報告只畫得出 details 裡的人，兩份清單若對不齊，對不齊的那個人會從報告上
  /// 整個消失 —— 那正是這次要修掉的那種靜默失蹤。
  RosterImportSummary toSummary() => RosterImportSummary(
    updated: updated,
    missingDates: missingDates,
    notInRosterNames: notInRosterNames,
    roleMismatchDetails: {
      for (final name in roleMismatchNames)
        name: roleMismatchDetails[name] ?? const [],
    },
    otherNames: otherNames,
    notInEventCatalog: notInEventCatalog,
  );
}
