import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/service_roster.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/domain/entities/user.dart';
import '../providers/roster_provider.dart';
import '../widgets/roster_view_card.dart';
import 'roster_edit_screen.dart' deferred as roster_edit_screen;

class RosterScreen extends StatefulWidget {
  const RosterScreen({super.key});

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
    } catch (error) {
      if (context.mounted) {
        if (dialogShown) {
          Navigator.of(context, rootNavigator: true).pop();
          dialogShown = false;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('載入失敗: $error')),
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
    final authProvider = context.watch<AuthProvider>();
    final isAdmin = authProvider.isAdmin;
    final userZones = authProvider.currentUser?.zones ?? const <UserZoneInfo>[];
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
    final isEditMode = context.watch<RosterProvider>().isEditMode;

    _updateTabController(allowedTypes.length);

    if (isEditMode && _editReady) {
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
        if (isAdmin)
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
        body: const Center(child: Text('尚未設定可檢視的牧區')),
      );
    }

    return DefaultTabController(
      length: allowedTypes.length,
      child: Scaffold(
        appBar: appBar,
        body: Consumer<RosterProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (provider.error != null) {
              return Center(child: Text(provider.error!));
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
                  rosters: provider.getRostersByType(type),
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
  final List<ServiceRoster> rosters;

  const _RosterViewList({super.key, required this.type, required this.rosters});

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

    if (widget.rosters.isEmpty) {
      return const Center(child: Text('此類別目前沒有服事資訊'));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 12, bottom: 20),
      itemCount: widget.rosters.length,
      itemBuilder: (context, index) {
        final roster = widget.rosters[index];
        return RosterViewCard(
          key: ValueKey(roster.id),
          roster: roster,
          initiallyExpanded: index == 0,
        );
      },
    );
  }
}
