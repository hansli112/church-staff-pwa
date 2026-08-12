import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/service_roster.dart';
import 'package:church_staff_pwa/core/types/service_type.dart';
import '../../../auth/presentation/providers/session_provider.dart';
import '../../../auth/domain/entities/user.dart';
import '../providers/roster_provider.dart';
import '../widgets/roster_view_card.dart';
import '../../../../core/utils/error_messages.dart';
import '../../../../core/widgets/empty_state.dart';
import 'roster_edit_screen.dart' deferred as roster_edit_screen;

class RosterScreen extends StatefulWidget {
  const RosterScreen({super.key, this.allowEdit = true});

  final bool allowEdit;

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen>
    with TickerProviderStateMixin {
  bool _editReady = false;
  bool _isLoadingEdit = false;
  TabController? _tabController;

  Future<void> _loadEditLibrary(
    BuildContext context,
    Future<void> Function() loadLibrary,
  ) async {
    if (_isLoadingEdit) return;
    _isLoadingEdit = true;
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
      setState(() {
        _editReady = true;
      });
      final rosterProvider = context.read<RosterProvider>();
      if (!rosterProvider.isEditMode) {
        rosterProvider.toggleEditMode();
      }
    } catch (error, st) {
      log('載入編輯模式失敗', error: error, stackTrace: st);
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
      _isLoadingEdit = false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rosterProvider = context.read<RosterProvider>();

      if (rosterProvider.rosters.isEmpty) {
        rosterProvider.fetchInitialData();
      }

      if (rosterProvider.isEditMode) {
        rosterProvider.toggleEditMode();
      }
    });
  }

  void _updateTabController(int length) {
    if (length <= 0) {
      _tabController?.dispose();
      _tabController = null;
      return;
    }
    if (_tabController == null || _tabController!.length != length) {
      final previousIndex = _tabController?.index ?? 0;
      _tabController?.dispose();
      _tabController = TabController(
        length: length,
        vsync: this,
        initialIndex: previousIndex.clamp(0, length - 1),
      );
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _exitEditMode() {
    final rosterProvider = context.read<RosterProvider>();
    if (rosterProvider.isEditMode) {
      rosterProvider.toggleEditMode();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final isAdmin = session.isAdmin;
    final canEdit = isAdmin && widget.allowEdit;
    final userZones = session.currentUser?.zones ?? const <UserZoneInfo>[];
    final allowedTypes = isAdmin
        ? ServiceType.values
        : ServiceType.values
              .where(
                (type) => userZones.any((zone) => zone.serviceType == type),
              )
              .toList();
    final now = DateTime.now();
    final quarterStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
    final isLastMonthOfQuarter = now.month == (quarterStartMonth + 2);
    final titleText = isLastMonthOfQuarter ? '本季/下季服事表' : '本季服事表';
    // select 而非 watch：否則每次 fetch 的 loading 開關都會重建整個 Scaffold
    // （含 AppBar / TabBar / TabController）。
    final isEditMode = context.select<RosterProvider, bool>(
      (provider) => provider.isEditMode,
    );

    _updateTabController(allowedTypes.length);

    if (isEditMode && _editReady && canEdit) {
      return roster_edit_screen.RosterEditScreen(
        onExit: _exitEditMode,
        tabController: _tabController,
        allowedTypes: allowedTypes,
      );
    }

    final appBar = AppBar(
      title: Text(titleText),
      centerTitle: true,
      actions: [
        if (canEdit)
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: '切換至編輯模式',
            onPressed: () =>
                _loadEditLibrary(context, roster_edit_screen.loadLibrary),
          ),
      ],
      bottom: allowedTypes.isEmpty
          ? null
          : TabBar(
              controller: _tabController,
              tabs: allowedTypes.map((type) => Tab(text: type.label)).toList(),
              indicatorSize: TabBarIndicatorSize.label,
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
          hint: '請聯絡管理員為您加入服事牧區',
        ),
      );
    }

    return DefaultTabController(
      length: allowedTypes.length,
      child: Scaffold(
        appBar: appBar,
        // 刻意不用 Consumer 包住整個 body：Consumer 會在每一次
        // notifyListeners 重建整棵 TabBarView，連帶產生全新的 ListView 與
        // 全新的卡片 widget，底下卡片再怎麼 select 也擋不住。改成只訂閱
        // 「要不要顯示 spinner／錯誤」這兩個 bool，清單自己去訂閱自己那份資料。
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

            return TabBarView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              controller: _tabController,
              children: allowedTypes.map((type) {
                return _RosterViewList(
                  key: PageStorageKey(type.toString()),
                  type: type,
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}

class _RosterViewList extends StatefulWidget {
  final ServiceType type;

  const _RosterViewList({super.key, required this.type});

  @override
  State<_RosterViewList> createState() => _RosterViewListState();
}

class _RosterViewListState extends State<_RosterViewList>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // 只訂閱這個牧區的清單。getRostersByType 有快取，資料沒變時回傳同一個
    // List instance，所以其他牧區被編輯、或單純的 loading 開關都不會重建這頁。
    final rosters = context.select<RosterProvider, List<ServiceRoster>>(
      (provider) => provider.getRostersByType(widget.type),
    );

    if (rosters.isEmpty) {
      return const EmptyState(
        icon: Icons.event_busy_outlined,
        message: '此類別目前沒有服事資訊',
        hint: '管理員建立後會在這裡顯示',
      );
    }

    // 事件選項換過就要重建（標籤顏色是從 provider 查的，不在 roster 裡）。
    context.select<RosterProvider, int>(
      (provider) => provider.eventOptionsRevision,
    );
    final rosterProvider = context.read<RosterProvider>();
    // 一個 closure 重複用，不要在 itemBuilder 裡每張卡各配一個。
    int resolveEventColor(String event) =>
        rosterProvider.eventColorFor(widget.type, event);

    return ListView.builder(
      padding: const EdgeInsets.only(top: 12, bottom: 20),
      itemCount: rosters.length,
      itemBuilder: (context, index) {
        final roster = rosters[index];
        return RosterViewCard(
          key: ValueKey(roster.id),
          roster: roster,
          initiallyExpanded: index == 0,
          resolveEventColor: resolveEventColor,
        );
      },
    );
  }
}
