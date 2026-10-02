import 'package:flutter/material.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';

class EventSheetResult {
  const EventSheetResult(this.events, {this.addToCommon = const []});

  final List<EventTag> events;

  /// Custom tags to keep as common options for this service.
  final List<EventTag> addToCommon;
}

/// Special-event tags for one day: tick the service's common ones, or add
/// a one-off with a colour (and, for admins, keep it as a common option).
class EventSheet extends StatefulWidget {
  const EventSheet({
    super.key,
    required this.options,
    required this.selected,
    required this.canAddToCommon,
  });

  final List<EventTag> options;
  final List<EventTag> selected;
  final bool canAddToCommon;

  @override
  State<EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends State<EventSheet> {
  late final List<EventTag> _selected = [...widget.selected];
  final _addToCommon = <EventTag>[];
  final _name = TextEditingController();
  int _color = 0;
  bool _keep = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Options plus tags already on the day that are not options.
  List<EventTag> get _all => [
    ...widget.options,
    for (final e in _selected)
      if (!widget.options.any((o) => o.name == e.name)) e,
  ];

  void _toggle(EventTag tag) {
    Haptics.selection();
    setState(() {
      final i = _selected.indexWhere((e) => e.name == tag.name);
      if (i >= 0) {
        _selected.removeAt(i);
      } else {
        _selected.add(tag);
      }
    });
  }

  void _addCustom() {
    final name = _name.text.trim();
    if (name.isEmpty || _all.any((e) => e.name == name)) return;
    final tag = EventTag(name: name, color: _color);
    setState(() {
      _selected.add(tag);
      if (_keep) _addToCommon.add(tag);
      _name.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.s, 0),
              child: Row(
                children: [
                  Expanded(child: Text(l10n.events, style: AppText.title3)),
                  SecondaryButton(
                    label: l10n.done,
                    onPressed: () => Navigator.pop(
                      context,
                      EventSheetResult(_selected, addToCommon: _addToCommon),
                    ),
                  ),
                ],
              ),
            ),
            if (_all.isNotEmpty)
              ListSection(
                children: [
                  for (final tag in _all)
                    ListRow(
                      title: tag.name,
                      leading: Tag.event(context, ' ', tag.color),
                      selected: _selected.any((e) => e.name == tag.name),
                      onTap: () => _toggle(tag),
                    ),
                ],
              ),
            ListSection(
              header: l10n.customEvent,
              children: [
                Padding(
                  padding: const EdgeInsets.all(Space.s),
                  child: TextField(
                    controller: _name,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(hintText: l10n.eventName),
                    onSubmitted: (_) => _addCustom(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.s,
                    vertical: Space.xs,
                  ),
                  child: Wrap(
                    spacing: Space.s,
                    children: [
                      for (var i = 0; i < EventColors.count; i++)
                        _ColorDot(
                          index: i,
                          label: _colorName(l10n, i),
                          selected: _color == i,
                          onTap: () => setState(() => _color = i),
                        ),
                    ],
                  ),
                ),
                if (widget.canAddToCommon)
                  SwitchRow(
                    title: l10n.addToCommon,
                    value: _keep,
                    onChanged: (v) => setState(() => _keep = v),
                  ),
                ListRow(
                  title: l10n.add,
                  leading: Icon(Icons.add, color: c.accent),
                  onTap: _addCustom,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _colorName(L10n l10n, int i) => switch (i) {
  0 => l10n.colorName0,
  1 => l10n.colorName1,
  2 => l10n.colorName2,
  3 => l10n.colorName3,
  4 => l10n.colorName4,
  _ => l10n.colorName5,
};

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.index,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = EventColors.of(context, index);
    final c = AppColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: colors.bg,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? c.label : colors.fg,
                  width: selected ? 3 : 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
