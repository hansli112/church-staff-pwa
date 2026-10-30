import 'dart:math';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/church_writes.dart';
import '../../state/providers.dart';
import '../../state/roster_actions.dart';
import '../rosters/future_changes.dart';
import '../common/errors.dart';
import '../common/labels.dart';
import '../common/saving_indicator.dart';

/// 服事設定: the church's services (聚會別). IDs only ever grow: a disabled
/// service keeps its old rosters and zones, and simply stops getting new
/// days.
class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final me = ref.watch(meProvider);
    if (!(me.value?.editsServiceSettings ?? false)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.serviceSettings)),
        body: me.hasValue ? EmptyState(message: l10n.servicesAdminOnly) : null,
      );
    }
    final settings = ref.watch(servicesProvider).value;
    if (settings == null) return Scaffold(appBar: AppBar());
    final list = settings.services;

    Future<void> save(List<Service> next) async {
      try {
        await ref.read(churchWritesProvider).serviceList(list, next).done;
      } catch (e) {
        if (context.mounted) showToast(context, saveErrorText(l10n, e));
      }
    }

    Future<void> add() async {
      final name = await promptText(
        context,
        title: l10n.serviceAdd,
        hint: l10n.serviceName,
      );
      if (name == null) return;
      final id = newServiceId(settings.ids);
      await save([
        ...list,
        Service(id: id, name: name, weekday: DateTime.sunday),
      ]);
      if (context.mounted) await context.push('/me/services/$id');
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.serviceSettings), actions: const [SavingIndicator()]),
      body: CustomScrollView(
        slivers: [
          ReorderableSection<Service>(
            header: l10n.servicesTitle,
            footer: l10n.serviceDisabledFooter,
            items: list,
            keyOf: (s) => s.id,
            onReorder: save,
            row: (s, handle) => ListRow(
              title: s.name,
              subtitle: s.enabled
                  ? weekdayLabel(l10n, s.weekday)
                  : '${weekdayLabel(l10n, s.weekday)}${l10n.dotSeparator}${l10n.serviceDisabled}',
              trailing: handle,
              onTap: () => context.push('/me/services/${s.id}'),
            ),
            after: [
              ListRow(
                title: l10n.serviceAdd,
                leading: const Icon(Symbols.add_rounded),
                onTap: add,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A fresh service ID that was never used in this church.
String newServiceId(List<String> taken) {
  final rng = Random();
  while (true) {
    final id = 's${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${rng.nextInt(1296).toRadixString(36)}';
    if (!taken.contains(id)) return id;
  }
}

/// One service: name, weekday, whether it still runs, its roster template
/// and its common special events.
class ServiceEditorScreen extends ConsumerWidget {
  const ServiceEditorScreen({super.key, required this.serviceId});

  final String serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final me = ref.watch(meProvider);
    if (!(me.value?.editsServiceSettings ?? false)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.serviceSettings)),
        body: me.hasValue ? EmptyState(message: l10n.servicesAdminOnly) : null,
      );
    }
    final settings = ref.watch(servicesProvider).value;
    final service = settings?.byId(serviceId);
    if (settings == null || service == null) return Scaffold(appBar: AppBar());
    // Keep future preview inputs live; no assignment is changed by editing
    // a configured option until the separate synchronization is applied.
    final future = ref.watch(savedRostersProvider);
    final today = ref.watch(todayProvider);
    final oldDuties = <String>{
      for (final r in future.value ?? const <Roster>[])
        if (r.type == serviceId && r.day.isAfter(today))
          for (final d in r.duties)
            if (!service.duties.contains(d.role)) d.role,
    }.toList()..sort();
    final oldEvents = <String>{
      for (final r in future.value ?? const <Roster>[])
        if (r.type == serviceId && r.day.isAfter(today))
          for (final e in r.events)
            if (!service.events.any((option) => option.name == e.name)) e.name,
    }.toList()..sort();

    Future<bool> save(Service next, {String? message, ({String from, String to})? dutyRename}) => runWithUndo(
      context,
      message ?? L10n.of(context).serviceSettingsSaved,
      () => ref.read(churchWritesProvider).service(service, next, dutyRename: dutyRename),
    );

    Future<void> synchronize(String target, {String? from, bool event = false}) async {
      final original =
          from ??
          await showAppSheet<String>(
            context,
            builder: (context) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListSection(
                    header: event
                        ? L10n.of(context).serviceSyncOriginalEvent
                        : L10n.of(context).serviceSyncOriginalDuty,
                    children: [
                      for (final name in event ? oldEvents : oldDuties)
                        ListRow(title: name, onTap: () => Navigator.pop(context, name)),
                    ],
                  ),
                ],
              ),
            ),
          );
      if (original == null || !context.mounted) return;
      final actions = ref.read(rosterActionsProvider);
      final preview = event
          ? actions.previewEventRename(serviceId, original, target)
          : actions.previewDutyRename(serviceId, original, target);
      if (preview.plan.isEmpty && preview.plan.conflicts.isEmpty) return;
      final apply = await showFutureRosterPreview(
        context,
        title: L10n.of(context).serviceFutureSyncTitle(original, target),
        preview: preview,
        today: ref.read(todayProvider),
      );
      if (!apply || !context.mounted) return;
      await runWithUndo(
        context,
        L10n.of(context).serviceFutureSyncSaved(preview.plan.before.length),
        () => actions.applyFuturePreview(preview),
      );
    }

    Future<void> renameDuty(String from) async {
      final to = await promptText(
        context,
        title: l10n.rename,
        hint: l10n.dutyName,
        initial: from,
      );
      if (to == null || to == from || service.duties.contains(to)) return;
      final saved = await save(
        service.copyWith(duties: [for (final d in service.duties) d == from ? to : d]),
        dutyRename: (from: from, to: to),
      );
      if (!saved || !context.mounted) return;
      await synchronize(to, from: from);
    }

    Future<void> renameEvent(EventTag from) async {
      final to = await promptText(
        context,
        title: l10n.rename,
        hint: l10n.eventName,
        initial: from.name,
      );
      if (to == null || to == from.name || service.events.any((e) => e.name == to)) return;
      final renamed = EventTag(name: to, color: from.color);
      final saved = await save(
        service.copyWith(
          events: [
            for (final e in service.events) e.name == from.name ? renamed : e,
          ],
        ),
      );
      if (!saved || !context.mounted) return;
      await synchronize(to, from: from.name, event: true);
    }

    Future<void> removeDuty(String d) async {
      await save(
        service.copyWith(
          duties: [
            for (final x in service.duties)
              if (x != d) x,
          ],
        ),
        message: l10n.dutyRemoved(d),
      );
    }

    Future<void> removeEvent(EventTag e) async {
      await save(
        service.copyWith(
          events: [
            for (final x in service.events)
              if (x.name != e.name) x,
          ],
        ),
        message: l10n.removed(e.name),
      );
    }

    Future<void> editColor(EventTag event) async {
      final color = await showAppSheet<int>(
        context,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            child: ListSection(
              header: L10n.of(context).serviceEventColorTitle(event.name),
              children: [
                for (final (i, name) in [
                  l10n.colorName0,
                  l10n.colorName1,
                  l10n.colorName2,
                  l10n.colorName3,
                  l10n.colorName4,
                  l10n.colorName5,
                ].indexed)
                  ListRow(
                    title: name,
                    leading: Tag.event(context, ' ', i),
                    selected: i == event.color,
                    onTap: () => Navigator.pop(context, i),
                  ),
              ],
            ),
          ),
        ),
      );
      if (color == null || color == event.color || !context.mounted) return;
      await save(
        service.copyWith(
          events: [
            for (final e in service.events) e.name == event.name ? EventTag(name: e.name, color: color) : e,
          ],
        ),
      );
    }

    /// Tapping a duty or an event: rename or remove it. Swiping the row
    /// removes it too.
    Future<void> rowActions(
      String name, {
      required Future<void> Function() rename,
      required Future<void> Function() remove,
      Future<void> Function()? color,
      Future<void> Function()? synchronize,
    }) async {
      final choice = await showAppSheet<String>(
        context,
        builder: (context) => SafeArea(
          child: ListSection(
            header: name,
            children: [
              ListRow(
                title: l10n.rename,
                leading: const Icon(Symbols.edit_rounded),
                onTap: () => Navigator.pop(context, 'rename'),
              ),
              if (color != null)
                ListRow(
                  title: L10n.of(context).serviceEventColor,
                  leading: const Icon(Symbols.palette_rounded),
                  onTap: () => Navigator.pop(context, 'color'),
                ),
              if (synchronize != null)
                ListRow(
                  title: L10n.of(context).serviceSyncFutureRosters,
                  leading: const Icon(Symbols.event_repeat_rounded),
                  onTap: () => Navigator.pop(context, 'synchronize'),
                ),
              ListRow(
                title: l10n.remove,
                destructive: true,
                leading: const Icon(Symbols.delete_rounded),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
            ],
          ),
        ),
      );
      if (!context.mounted) return;
      switch (choice) {
        case 'rename':
          await rename();
        case 'color':
          await color?.call();
        case 'synchronize':
          await synchronize?.call();
        case 'remove':
          await remove();
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(service.name), actions: const [SavingIndicator()]),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: ListSection(
              children: [
                ListRow(
                  title: l10n.serviceName,
                  value: service.name,
                  onTap: () async {
                    final name = await promptText(
                      context,
                      title: l10n.rename,
                      hint: l10n.serviceName,
                      initial: service.name,
                    );
                    if (name != null) await save(service.copyWith(name: name));
                  },
                ),
                ListRow(
                  title: l10n.weekday,
                  value: weekdayLabel(l10n, service.weekday),
                  onTap: () async {
                    final day = await showAppSheet<int>(
                      context,
                      builder: (context) => SafeArea(
                        child: SingleChildScrollView(
                          child: ListSection(
                            header: l10n.weekday,
                            children: [
                              for (var d = 1; d <= 7; d++)
                                ListRow(
                                  title: weekdayLabel(l10n, d),
                                  selected: service.weekday == d,
                                  onTap: () => Navigator.pop(context, d),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                    if (day != null) await save(service.copyWith(weekday: day));
                  },
                ),
                SwitchRow(
                  title: l10n.serviceEnabled,
                  value: service.enabled,
                  onChanged: (v) => save(service.copyWith(enabled: v)),
                ),
              ],
            ),
          ),
          ReorderableSection<String>(
            header: l10n.templateDuties,
            footer: l10n.templateFooter,
            items: service.duties,
            keyOf: (d) => 'duty/$d',
            onReorder: (next) => save(service.copyWith(duties: next)),
            row: (d, handle) => Dismissible(
              key: ValueKey('duty/$d'),
              direction: DismissDirection.endToStart,
              background: const SwipeDeleteBackground(),
              confirmDismiss: (_) async {
                await removeDuty(d);
                return false; // The successful server change removes the row.
              },
              child: ListRow(
                title: d,
                onTap: () => rowActions(
                  d,
                  rename: () => renameDuty(d),
                  remove: () => removeDuty(d),
                  synchronize: oldDuties.isEmpty ? null : () => synchronize(d),
                ),
                trailing: handle,
              ),
            ),
            after: [
              ListRow(
                title: l10n.addDuty,
                leading: const Icon(Symbols.add_rounded),
                onTap: () async {
                  final name = await promptText(
                    context,
                    title: l10n.addDuty,
                    hint: l10n.dutyName,
                  );
                  if (name != null && !service.duties.contains(name)) {
                    await save(
                      service.copyWith(duties: [...service.duties, name]),
                    );
                  }
                },
              ),
            ],
          ),
          ReorderableSection<EventTag>(
            header: l10n.commonEvents,
            items: service.events,
            keyOf: (e) => 'event/${e.name}',
            onReorder: (next) => save(service.copyWith(events: next)),
            row: (e, handle) => Dismissible(
              key: ValueKey('event/${e.name}'),
              direction: DismissDirection.endToStart,
              background: const SwipeDeleteBackground(),
              confirmDismiss: (_) async {
                await removeEvent(e);
                return false;
              },
              child: ListRow(
                title: e.name,
                leading: Tag.event(context, ' ', e.color),
                trailing: handle,
                onTap: () => rowActions(
                  e.name,
                  rename: () => renameEvent(e),
                  color: () => editColor(e),
                  remove: () => removeEvent(e),
                  synchronize: oldEvents.isEmpty ? null : () => synchronize(e.name, event: true),
                ),
              ),
            ),
            after: [
              ListRow(
                title: l10n.addEvent,
                leading: const Icon(Symbols.add_rounded),
                onTap: () async {
                  final name = await promptText(
                    context,
                    title: l10n.customEvent,
                    hint: l10n.eventName,
                  );
                  if (name != null && !service.events.any((e) => e.name == name)) {
                    await save(
                      service.copyWith(
                        events: [
                          ...service.events,
                          EventTag(
                            name: name,
                            color: service.events.length % 6,
                          ),
                        ],
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
