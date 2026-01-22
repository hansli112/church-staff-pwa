import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/service_roster.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/roster_provider.dart';
import '../widgets/roster_card.dart';
import 'role_settings_screen.dart';

class RosterScreen extends StatefulWidget {
  const RosterScreen({super.key});

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rosterProvider = context.read<RosterProvider>();
      final authProvider = context.read<AuthProvider>();

      if (rosterProvider.rosters.isEmpty) {
        rosterProvider.fetchInitialData();
      }

      // Ensure edit mode is disabled if not an admin (safety check)
      if (!authProvider.isAdmin && rosterProvider.isEditMode) {
        rosterProvider.toggleEditMode();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.select<AuthProvider, bool>((auth) => auth.isAdmin);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Consumer<RosterProvider>(
            builder: (context, provider, child) {
              return Text(provider.isEditMode ? '編輯服事表' : '本季服事表');
            },
          ),
          centerTitle: true,
          actions: [
            if (isAdmin) ...[
              Consumer<RosterProvider>(
                builder: (context, provider, child) {
                  if (!provider.isEditMode) return const SizedBox.shrink();
                  return IconButton(
                    icon: const Icon(Icons.settings),
                    tooltip: '服事項目設定',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RoleSettingsScreen()),
                    ),
                  );
                },
              ),
              Consumer<RosterProvider>(
                builder: (context, provider, child) {
                  return IconButton(
                    icon: Icon(provider.isEditMode ? Icons.view_list : Icons.edit),
                    tooltip: provider.isEditMode ? '切換至檢視模式' : '切換至編輯模式',
                    onPressed: () => provider.toggleEditMode(),
                  );
                },
              ),
            ],
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: '主日'),
              Tab(text: '青崇'),
              Tab(text: '兒主'),
            ],
            indicatorSize: TabBarIndicatorSize.label,
            // 讓切換時的動畫更平滑
            splashFactory: NoSplash.splashFactory,
            overlayColor: WidgetStatePropertyAll(Colors.transparent),
          ),
        ),
        body: Consumer<RosterProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (provider.error != null) {
              return Center(child: Text(provider.error!));
            }

            // TabBarView 預設支援左右滑動
            return TabBarView(
              // 結合 BouncingScrollPhysics 產生彈性，同時保持分頁吸附感
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              children: [
                _RosterList(
                  key: const PageStorageKey('sunday'),
                  rosters: provider.getRostersByType(ServiceType.sundayService),
                ),
                _RosterList(
                  key: const PageStorageKey('youth'),
                  rosters: provider.getRostersByType(ServiceType.youth),
                ),
                _RosterList(
                  key: const PageStorageKey('children'),
                  rosters: provider.getRostersByType(ServiceType.children),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RosterList extends StatefulWidget {
  final List<ServiceRoster> rosters;

  const _RosterList({super.key, required this.rosters});

  @override
  State<_RosterList> createState() => _RosterListState();
}

// 使用 AutomaticKeepAliveClientMixin 來保持滑動位置
class _RosterListState extends State<_RosterList> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // 告訴 Flutter 保持這個頁面的狀態

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必須呼叫 super.build
    
    if (widget.rosters.isEmpty) {
      return const Center(child: Text('此類別目前沒有服事資訊'));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 12, bottom: 20),
      itemCount: widget.rosters.length,
              itemBuilder: (context, index) {
                final roster = widget.rosters[index];
                return RosterCard(
                  key: ValueKey(roster.id),
                  roster: roster,
                  initiallyExpanded: index == 0,
                );
              },    );
  }
}