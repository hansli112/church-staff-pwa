import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/church_writes.dart';
import '../../state/providers.dart';
import '../../state/roster_actions.dart';
import '../rosters/future_changes.dart';
import '../common/errors.dart';
import '../common/labels.dart';

/// 服事設定: the church's services (聚會別). IDs only ever grow: a disabled
/// service keeps its old rosters and zones, and simply stops getting new
/// days.
class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final me = ref.watch(meProvider);
    if (!(me.value?.isAdmin ?? false)) {
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
      appBar: AppBar(title: Text(l10n.serviceSettings)),
      body: ListView(
        children: [
          ListSection(
            header: l10n.servicesTitle,
            footer: l10n.serviceDisabledFooter,
            children: [
              for (final (i, s) in list.indexed)
                ListRow(
                  title: s.name,
                  subtitle: s.enabled
                      ? weekdayLabel(l10n, s.weekday)
                      : '${weekdayLabel(l10n, s.weekday)}${l10n.dotSeparator}${l10n.serviceDisabled}',
                  trailing: list.length < 2
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: l10n.moveUp,
                              icon: const Icon(Icons.arrow_upward),
                              onPressed: i == 0 ? null : () => save([...list]..swap(i, i - 1)),
                            ),
                            IconButton(
                              tooltip: l10n.moveDown,
                              icon: const Icon(Icons.arrow_downward),
                              onPressed: i == list.length - 1 ? null : () => save([...list]..swap(i, i + 1)),
                            ),
                          ],
                        ),
                  onTap: () => context.push('/me/services/${s.id}'),
                ),
              ListRow(
                title: l10n.serviceAdd,
                leading: const Icon(Icons.add),
                onTap: add,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

extension<T> on List<T> {
  void swap(int a, int b) {
    final t = this[a];
    this[a] = this[b];
    this[b] = t;
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

/// Asks for one line of text. Null when cancelled or empty.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String hint,
  String initial = '',
  int? maxLength,
}) async {
  final result = await showAdaptiveDialog<String>(
    context: context,
    builder: (context) => _PromptDialog(title: title, hint: hint, initial: initial, maxLength: maxLength),
  );
  final t = result?.trim();
  return t == null || t.isEmpty ? null : t;
}

/// Owns its text controller, so the controller outlives the closing
/// animation.
class _PromptDialog extends StatefulWidget {
  const _PromptDialog({required this.title, required this.hint, required this.initial, this.maxLength});

  final String title;
  final String hint;
  final String initial;
  final int? maxLength;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: widget.maxLength,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        TextButton(onPressed: () => Navigator.pop(context, _controller.text), child: Text(l10n.save)),
      ],
    );
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
    if (!(me.value?.isAdmin ?? false)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.serviceSettings)),
        body: me.hasValue ? EmptyState(message: l10n.servicesAdminOnly) : null,
      );
    }
    final c = AppColors.of(context);
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
                leading: const Icon(Icons.edit_outlined),
                onTap: () => Navigator.pop(context, 'rename'),
              ),
              if (color != null)
                ListRow(
                  title: L10n.of(context).serviceEventColor,
                  leading: const Icon(Icons.palette_outlined),
                  onTap: () => Navigator.pop(context, 'color'),
                ),
              if (synchronize != null)
                ListRow(
                  title: L10n.of(context).serviceSyncFutureRosters,
                  leading: const Icon(Icons.event_repeat_outlined),
                  onTap: () => Navigator.pop(context, 'synchronize'),
                ),
              ListRow(
                title: l10n.remove,
                destructive: true,
                leading: const Icon(Icons.delete_outline),
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
      appBar: AppBar(title: Text(service.name)),
      body: ListView(
        children: [
          ListSection(
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
          ListSection(
            header: l10n.templateDuties,
            footer: l10n.templateFooter,
            children: [
              for (final (i, d) in service.duties.indexed)
                Dismissible(
                  key: ValueKey('duty/$d'),
                  direction: DismissDirection.endToStart,
                  background: Container(color: c.destructive),
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
                    // Up and down, like the common events below.
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: l10n.moveUp,
                          icon: const Icon(Icons.arrow_upward),
                          onPressed: i == 0
                              ? null
                              : () => save(service.copyWith(duties: [...service.duties]..swap(i, i - 1))),
                        ),
                        IconButton(
                          tooltip: l10n.moveDown,
                          icon: const Icon(Icons.arrow_downward),
                          onPressed: i == service.duties.length - 1
                              ? null
                              : () => save(service.copyWith(duties: [...service.duties]..swap(i, i + 1))),
                        ),
                      ],
                    ),
                  ),
                ),
              ListRow(
                title: l10n.addDuty,
                leading: const Icon(Icons.add),
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
          ListSection(
            header: l10n.commonEvents,
            children: [
              for (final (i, e) in service.events.indexed)
                Dismissible(
                  key: ValueKey('event/${e.name}'),
                  direction: DismissDirection.endToStart,
                  background: Container(color: c.destructive),
                  confirmDismiss: (_) async {
                    await removeEvent(e);
                    return false;
                  },
                  child: ListRow(
                    title: e.name,
                    leading: Tag.event(context, ' ', e.color),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: l10n.moveUp,
                          icon: const Icon(Icons.arrow_upward),
                          onPressed: i == 0
                              ? null
                              : () => save(service.copyWith(events: [...service.events]..swap(i, i - 1))),
                        ),
                        IconButton(
                          tooltip: l10n.moveDown,
                          icon: const Icon(Icons.arrow_downward),
                          onPressed: i == service.events.length - 1
                              ? null
                              : () => save(service.copyWith(events: [...service.events]..swap(i, i + 1))),
                        ),
                      ],
                    ),
                    onTap: () => rowActions(
                      e.name,
                      rename: () => renameEvent(e),
                      color: () => editColor(e),
                      remove: () => removeEvent(e),
                      synchronize: oldEvents.isEmpty ? null : () => synchronize(e.name, event: true),
                    ),
                  ),
                ),
              ListRow(
                title: l10n.addEvent,
                leading: const Icon(Icons.add),
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
