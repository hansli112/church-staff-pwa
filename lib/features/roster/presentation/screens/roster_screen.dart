import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/service_roster.dart';
import '../providers/roster_provider.dart';
import '../widgets/roster_card.dart';

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
      final provider = context.read<RosterProvider>();
      if (provider.rosters.isEmpty) {
        provider.fetchRosters();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('本季服事表'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => context.read<RosterProvider>().fetchRosters(),
            ),
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
        return RosterCard(
          roster: widget.rosters[index],
          initiallyExpanded: index == 0,
        );
      },
    );
  }
}