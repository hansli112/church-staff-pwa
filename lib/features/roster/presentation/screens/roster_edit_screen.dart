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
import '../../../../core/utils/snappy_page_scroll_physics.dart';
import '../../../../core/widgets/settings_bottom_sheet.dart';
import '../../../../core/widgets/text_controller_scope.dart';
import 'event_settings_screen.dart' deferred as event_settings_screen;
import 'role_settings_screen.dart' deferred as role_settings_screen;
import 'roster_import_parser.dart';

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

      if (!session.isAdmin) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('沒有權限進入編輯模式')));
        widget.onExit();
        return;
      }

      // Admin 進入編輯模式時，背景補齊本季 + 下季的 roster（backfill）。
      // 在非 admin 路徑下已 return，此處一定是 admin。
      // 失敗靜默處理（ensureQuarterRostersIfAdmin 內部 catch），不影響 UI。
      context.read<RosterProvider>().ensureQuarterRostersIfAdmin();
    });
  }

  @override
  Widget build(BuildContext context) {
    final allowedTypes = widget.allowedTypes;
    final now = DateTime.now();
    final quarterStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
    final isLastMonthOfQuarter = now.month == (quarterStartMonth + 2);
    final titleText = isLastMonthOfQuarter ? '編輯本季/下季服事表' : '編輯本季服事表';

    final appBar = AppBar(
      title: Text(titleText),
      centerTitle: true,
      actions: [
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
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // 告訴 Flutter 保持這個頁面的狀態

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
      padding: const EdgeInsets.only(top: 12, bottom: 20),
      itemCount: rosters.length + (showImport ? 1 : 0),
      itemBuilder: (context, index) {
        if (showImport && index == 0) {
          return _buildImportCard(context);
        }
        final rosterIndex = index - (showImport ? 1 : 0);
        final roster = rosters[rosterIndex];
        return RosterCard(
          key: ValueKey(roster.id),
          roster: roster,
          initiallyExpanded: rosterIndex == 0,
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
                        if (result.missingDates.isNotEmpty ||
                            result.notInRosterNames.isNotEmpty ||
                            result.roleMismatchNames.isNotEmpty ||
                            result.otherNames.isNotEmpty ||
                            result.notInEventCatalog.isNotEmpty) {
                          if (!context.mounted) return;
                          await _showImportSummaryDialog(context, result);
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

  String _buildResultMessage(_JsonImportResult result) {
    if (result.updated == 0 && result.notInEventCatalog.isEmpty) {
      return '找不到可更新的日期';
    }
    if (result.missingDates.isEmpty &&
        result.notInRosterNames.isEmpty &&
        result.roleMismatchNames.isEmpty &&
        result.otherNames.isEmpty &&
        result.notInEventCatalog.isEmpty) {
      return '已更新 ${result.updated} 筆服事表';
    }
    final missingPreview = result.missingDates.take(3).join(', ');
    final missingSuffix = result.missingDates.length > 3 ? '...' : '';
    final notInListPreview = result.notInRosterNames.take(3).join('、');
    final notInListSuffix = result.notInRosterNames.length > 3 ? '...' : '';
    final mismatchPreview = result.roleMismatchNames.take(3).join('、');
    final mismatchSuffix = result.roleMismatchNames.length > 3 ? '...' : '';
    final otherPreview = result.otherNames.take(3).join('、');
    final otherSuffix = result.otherNames.length > 3 ? '...' : '';
    final catalogPreview = result.notInEventCatalog.take(3).join('、');
    final catalogSuffix = result.notInEventCatalog.length > 3 ? '...' : '';
    final parts = <String>[];
    if (result.missingDates.isNotEmpty) {
      parts.add(
        '${result.missingDates.length} 筆日期找不到：$missingPreview$missingSuffix',
      );
    }
    if (result.notInRosterNames.isNotEmpty) {
      parts.add(
        '${result.notInRosterNames.length} 位不在名單：$notInListPreview$notInListSuffix',
      );
    }
    if (result.roleMismatchNames.isNotEmpty) {
      parts.add(
        '${result.roleMismatchNames.length} 位未勾選該服事：$mismatchPreview$mismatchSuffix',
      );
    }
    if (result.otherNames.isNotEmpty) {
      parts.add('${result.otherNames.length} 位其它：$otherPreview$otherSuffix');
    }
    if (result.notInEventCatalog.isNotEmpty) {
      parts.add(
        '${result.notInEventCatalog.length} 個不在事件選單：$catalogPreview$catalogSuffix',
      );
    }
    return '已更新 ${result.updated} 筆，${parts.join('；')}';
  }

  String _buildResultDetails(_JsonImportResult result) {
    final buffer = StringBuffer();
    buffer.writeln('已更新 ${result.updated} 筆服事表');
    if (result.missingDates.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('找不到的日期：');
      for (final date in result.missingDates) {
        buffer.writeln('- $date');
      }
    }
    if (result.notInRosterNames.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('不在名單：');
      for (final name in result.notInRosterNames) {
        buffer.writeln('- $name');
      }
    }
    if (result.roleMismatchNames.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('未勾選該服事：');
      for (final name in result.roleMismatchNames) {
        final roles = result.roleMismatchDetails[name];
        if (roles == null || roles.isEmpty) {
          buffer.writeln('- $name');
        } else {
          buffer.writeln('- $name：${roles.join('、')}');
        }
      }
    }
    if (result.otherNames.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('其它：');
      for (final name in result.otherNames) {
        buffer.writeln('- $name');
      }
    }
    if (result.notInEventCatalog.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('不在事件選單：');
      for (final name in result.notInEventCatalog) {
        buffer.writeln('- $name');
      }
    }
    return buffer.toString().trim();
  }

  Future<void> _showImportSummaryDialog(
    BuildContext context,
    _JsonImportResult result,
  ) async {
    final details = _buildResultDetails(result);
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('匯入完成（含未匹配）'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(child: SelectableText(details)),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('關閉'),
            ),
          ],
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
    final roleOrder = {
      for (var i = 0; i < templateRoles.length; i++) templateRoles[i]: i,
    };

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
        final rawDuties = parsed.dutiesByDate[key] ?? const [];
        newDuties = List<RosterEntry>.from(rawDuties)
          ..sort((a, b) {
            final ai = roleOrder[a.role] ?? templateRoles.length;
            final bi = roleOrder[b.role] ?? templateRoles.length;
            if (ai != bi) return ai.compareTo(bi);
            return rawDuties.indexOf(a).compareTo(rawDuties.indexOf(b));
          });
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
}
