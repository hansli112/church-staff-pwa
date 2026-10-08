import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import 'roster_card.dart';

/// Remembers which service tab was open, per device.
class SelectedService extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String id) => state = id;
}

final selectedServiceProvider = NotifierProvider<SelectedService, String?>(
  SelectedService.new,
);

/// The 服事表 tab: upcoming days of one service at a time, with a switch
/// between services when it shows more than one. A member sees the 牧區
/// they belong to; admins and roster editors see every service.
///
/// Self-host collapsed every day into an expansion tile and had a separate
/// edit mode. Here every day shows its people at once; tapping a day opens
/// it, where editors edit.
class RostersScreen extends ConsumerWidget {
  const RostersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(servicesProvider);
    final meValue = ref.watch(meProvider);
    final me = meValue.value;
    final mine = me?.rosterServices(settings.value?.enabled ?? const []) ?? const <Service>[];
    final selectedId = ref.watch(selectedServiceProvider);
    final shown = mine.where((s) => s.id == selectedId).firstOrNull ?? mine.firstOrNull;
    final canImport = shown != null && (me?.canEditRosters(shown.id) ?? false);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tabRosters),
        actions: [
          if (canImport)
            IconButton(
              tooltip: l10n.photoImport,
              icon: const Icon(Icons.document_scanner_outlined),
              onPressed: () => context.push('/rosters/import/${shown.id}'),
            ),
        ],
      ),
      body: settings.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => ErrorRetry(
          message: l10n.loadFailed,
          onRetry: () => ref.invalidate(servicesProvider),
        ),
        data: (settings) {
          if (settings.enabled.isEmpty) {
            return EmptyState(
              message: l10n.noServicesConfigured,
              actionLabel: (me?.isAdmin ?? false) ? l10n.setUpServices : null,
              onAction: () => context.push('/me/services'),
            );
          }
          // Which services are mine waits for my member doc.
          if (meValue.hasError) {
            return ErrorRetry(message: l10n.loadFailed, onRetry: () => ref.invalidate(meProvider));
          }
          if (me == null) return const SizedBox.shrink();
          if (shown == null) return EmptyState(message: l10n.noZoneYet);
          return Column(
            children: [
              if (mine.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.m,
                    0,
                    Space.m,
                    Space.s,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: [
                        for (final s in mine)
                          ButtonSegment(
                            value: s.id,
                            label: Text(s.name, maxLines: 1),
                          ),
                      ],
                      selected: {shown.id},
                      onSelectionChanged: (v) {
                        Haptics.selection();
                        ref.read(selectedServiceProvider.notifier).select(v.first);
                      },
                    ),
                  ),
                ),
              Expanded(child: ServiceRosterList(service: shown)),
            ],
          );
        },
      ),
    );
  }
}

/// The days of one service. Rebuilds only when the set of days changes;
/// each card watches its own day.
class ServiceRosterList extends ConsumerWidget {
  const ServiceRosterList({super.key, required this.service});

  final Service service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final ids = ref.watch(
      serviceRostersProvider(
        service.id,
      ).select((v) => v.whenData((l) => [for (final r in l) r.id].join('|'))),
    );
    return ids.when(
      skipLoadingOnReload: true,
      loading: () => const SizedBox.shrink(),
      error: (_, _) => ErrorRetry(
        message: l10n.loadFailed,
        onRetry: () => ref.invalidate(savedRostersProvider),
      ),
      data: (joined) {
        final list = joined.isEmpty ? const <String>[] : joined.split('|');
        if (list.isEmpty) return EmptyState(message: l10n.noRostersAhead);
        return ListView.builder(
          key: PageStorageKey('rosters-${service.id}'),
          padding: const EdgeInsets.only(bottom: Space.l),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final id = list[i];
            return RosterCard(
              key: ValueKey(id),
              serviceType: service.id,
              rosterId: id,
              onTap: () => context.push('/rosters/${service.id}/${id.split('_').first}'),
            );
          },
        );
      },
    );
  }
}
