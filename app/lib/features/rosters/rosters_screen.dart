import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
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
    final ministries = ref.watch(ministriesProvider).value?.ministries ?? const <Ministry>[];
    final mine = me?.rosterServices(settings.value?.enabled ?? const [], ministries: ministries) ?? const <Service>[];
    final selectedId = ref.watch(selectedServiceProvider);
    final shown = mine.where((s) => s.id == selectedId).firstOrNull ?? mine.firstOrNull;
    final canImport = shown != null && ref.watch(arrangesProvider(shown.id)).any;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tabRosters),
        actions: [
          if (canImport)
            IconButton(
              icon: const Icon(Symbols.calendar_view_month_rounded),
              tooltip: l10n.planWeeksAction,
              onPressed: () => context.push('/rosters/plan/${shown.id}'),
            ),
          // In words: no icon says "read a roster from a photo" at a glance.
          // Grows with the text only so far, like the bar's own buttons, so
          // the title beside it keeps its room.
          if (canImport)
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.5,
              child: TextButton(
                onPressed: () => context.push('/rosters/import/${shown.id}'),
                child: Text(l10n.photoImportAction),
              ),
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
              icon: Symbols.view_agenda_rounded,
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
          if (shown == null) return EmptyState(icon: Symbols.group_rounded, message: l10n.noZoneYet);
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
    // A new church, or one nobody has arranged ahead yet: every day reads
    // 待定. Those who may arrange it get one way in, to the first day.
    final nobodyArranged =
        ref.watch(meProvider.select((m) => m.value?.canEditRosters(service.id) ?? false)) &&
        ref.watch(
          serviceRostersProvider(service.id).select(
            (v) => v.value?.every((r) => r.duties.every((d) => d.people.isEmpty)) ?? false,
          ),
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
        if (list.isEmpty) return EmptyState(icon: Symbols.view_agenda_rounded, message: l10n.noRostersAhead);
        void open(String id) => context.push('/rosters/${service.id}/${id.split('_').first}');
        final top = nobodyArranged ? 1 : 0;
        return ListView.builder(
          key: PageStorageKey('rosters-${service.id}'),
          padding: const EdgeInsets.only(bottom: Space.l),
          itemCount: top + list.length + (service.enabled ? 1 : 0),
          itemBuilder: (context, index) {
            if (index < top) {
              return _StartArranging(
                onStart: () => open(list.first),
                onImport: () => context.push('/rosters/import/${service.id}'),
              );
            }
            final i = index - top;
            if (i == list.length) {
              return Padding(
                padding: const EdgeInsets.all(Space.m),
                child: SecondaryButton(
                  label: l10n.rosterShowMore,
                  onPressed: () => ref.read(rosterWeeksProvider(service.id).notifier).showMore(),
                ),
              );
            }
            final id = list[i];
            return RosterCard(
              key: ValueKey(id),
              serviceType: service.id,
              rosterId: id,
              onTap: () => open(id),
            );
          },
        );
      },
    );
  }
}

/// One sentence above a service nobody is arranged in yet, and two ways
/// to start: by hand from the first day, or from a photo of a paper roster.
class _StartArranging extends StatelessWidget {
  const _StartArranging({required this.onStart, required this.onImport});

  final VoidCallback onStart;

  /// A roster already on paper needs no typing: read from a photo of it.
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
      child: Column(
        children: [
          BalancedText(l10n.rostersNobodyArranged, style: AppText.body.copyWith(color: c.secondaryLabel)),
          SecondaryButton(label: l10n.rostersStartArranging, onPressed: onStart),
          TextButton(onPressed: onImport, child: Text(l10n.rostersImportPhoto)),
        ],
      ),
    );
  }
}
