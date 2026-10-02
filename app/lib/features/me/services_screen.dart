import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../common/labels.dart';

/// 服事設定: the church's services (聚會別). IDs only ever grow: a disabled
/// service keeps its old rosters and zones, and simply stops getting new
/// days.
class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(servicesProvider).value;
    if (settings == null) return Scaffold(appBar: AppBar());
    final list = settings.services;

    Future<void> save(List<Service> next) async {
      try {
        await ref.read(churchDataProvider)!.saveServices(next);
      } catch (_) {
        if (context.mounted) showToast(context, l10n.saveFailed);
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
                      : '${weekdayLabel(l10n, s.weekday)}・${l10n.serviceDisabled}',
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
}) async {
  final result = await showAdaptiveDialog<String>(
    context: context,
    builder: (context) => _PromptDialog(title: title, hint: hint, initial: initial),
  );
  final t = result?.trim();
  return t == null || t.isEmpty ? null : t;
}

/// Owns its text controller, so the controller outlives the closing
/// animation.
class _PromptDialog extends StatefulWidget {
  const _PromptDialog({required this.title, required this.hint, required this.initial});

  final String title;
  final String hint;
  final String initial;

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
    final c = AppColors.of(context);
    final settings = ref.watch(servicesProvider).value;
    final service = settings?.byId(serviceId);
    if (settings == null || service == null) return Scaffold(appBar: AppBar());
    final data = ref.read(churchDataProvider)!;

    Future<void> save(Service next) async {
      try {
        await data.saveServices([
          for (final s in settings.services) s.id == serviceId ? next : s,
        ]);
      } catch (_) {
        if (context.mounted) showToast(context, l10n.saveFailed);
      }
    }

    Future<void> renameDuty(String from) async {
      final to = await promptText(
        context,
        title: l10n.rename,
        hint: l10n.dutyName,
        initial: from,
      );
      if (to == null || to == from || service.duties.contains(to)) return;
      await save(
        service.copyWith(
          duties: [for (final d in service.duties) d == from ? to : d],
        ),
      );
      // Zones and staff order are keyed by duty name: move them along so the
      // picker still lists the same people. Rosters already arranged keep
      // their old wording.
      final members = ref.read(membersProvider).value ?? const <Member>[];
      for (final m in members) {
        if (!m.serves(serviceId, from)) continue;
        await data.saveMember(
          m.copyWith(
            zones: [
              for (final z in m.zones)
                z.serviceType == serviceId
                    ? z.copyWith(
                        duties: [for (final d in z.duties) d == from ? to : d],
                      )
                    : z,
            ],
          ),
        );
      }
      final order = ref.read(staffOrderProvider(serviceId)).value;
      final ranking = order?.rankingOf(from) ?? const [];
      if (ranking.isNotEmpty) {
        await data.updateStaffOrder(serviceId, {from: null, to: ranking});
      }
    }

    Future<void> renameEvent(EventTag from) async {
      final to = await promptText(
        context,
        title: l10n.rename,
        hint: l10n.eventName,
        initial: from.name,
      );
      if (to == null || to == from.name) return;
      final renamed = EventTag(name: to, color: from.color);
      await save(
        service.copyWith(
          events: [
            for (final e in service.events) e.name == from.name ? renamed : e,
          ],
        ),
      );
      // Tags already on upcoming days follow the new name.
      final saved = ref.read(savedRostersProvider).value ?? const <Roster>[];
      final touched = [
        for (final r in saved)
          if (r.type == serviceId && r.events.any((e) => e.name == from.name))
            r.copyWith(
              events: [
                for (final e in r.events) e.name == from.name ? renamed : e,
              ],
            ),
      ];
      if (touched.isNotEmpty) await data.saveRosters(touched);
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
                  onDismissed: (_) {
                    final before = service;
                    save(
                      service.copyWith(
                        duties: [
                          for (final x in service.duties)
                            if (x != d) x,
                        ],
                      ),
                    );
                    showToast(
                      context,
                      l10n.dutyRemoved(d),
                      onUndo: () => save(before),
                    );
                  },
                  child: ListRow(
                    title: d,
                    onTap: () => renameDuty(d),
                    trailing: IconButton(
                      tooltip: l10n.moveUp,
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: i == 0
                          ? null
                          : () => save(
                              service.copyWith(
                                duties: [...service.duties]..swap(i, i - 1),
                              ),
                            ),
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
              for (final e in service.events)
                Dismissible(
                  key: ValueKey('event/${e.name}'),
                  direction: DismissDirection.endToStart,
                  background: Container(color: c.destructive),
                  onDismissed: (_) {
                    final before = service;
                    save(
                      service.copyWith(
                        events: [
                          for (final x in service.events)
                            if (x.name != e.name) x,
                        ],
                      ),
                    );
                    showToast(
                      context,
                      l10n.removed(e.name),
                      onUndo: () => save(before),
                    );
                  },
                  child: ListRow(
                    title: e.name,
                    leading: Tag.event(context, ' ', e.color),
                    onTap: () => renameEvent(e),
                  ),
                ),
              ListRow(
                title: l10n.add,
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
