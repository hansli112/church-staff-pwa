import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';

/// Special-event tags for one day: tick the service's common ones, or add
/// one for this day only from the list's last row (新增特別活動). The
/// common ones are set on the service's page.
class EventSheet extends StatefulWidget {
  const EventSheet({super.key, required this.options, required this.selected});

  final List<EventTag> options;
  final List<EventTag> selected;

  @override
  State<EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends State<EventSheet> {
  late final List<EventTag> _selected = [...widget.selected];
  final _name = TextEditingController();

  /// Typing a new one: the last row is a field, the colours under it.
  bool _adding = false;
  int _color = 0;

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

  void _startAdding() {
    final used = {for (final e in _all) e.color};
    setState(() {
      _adding = true;
      // One not on the list yet, so it tells apart from the rest.
      _color = [for (var i = 0; i < EventColors.count; i++) i].firstWhere((i) => !used.contains(i), orElse: () => 0);
    });
  }

  /// Adds what was typed, ticked, for this day; a name on the list already
  /// is ticked instead.
  void _addTyped() {
    final name = _name.text.trim();
    if (name.isNotEmpty) {
      final known = _all.where((e) => e.name == name).firstOrNull;
      if (known == null) {
        _selected.add(EventTag(name: name, color: _color));
      } else if (!_selected.any((e) => e.name == name)) {
        _selected.add(known);
      }
    }
    _name.clear();
    setState(() => _adding = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return UnsavedChanges(
      changed: () =>
          !setEquals({for (final e in _selected) e.name}, {for (final e in widget.selected) e.name}) ||
          _name.text.trim().isNotEmpty,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetBar(
                title: l10n.events,
                actions: [
                  SecondaryButton(
                    label: l10n.done,
                    onPressed: () {
                      // Typed but not entered yet: meant all the same.
                      if (_name.text.trim().isNotEmpty) _addTyped();
                      Navigator.pop(context, _selected);
                    },
                  ),
                ],
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListSection(
                      children: [
                        for (final tag in _all)
                          ListRow(
                            title: tag.name,
                            leading: Tag.event(context, ' ', tag.color),
                            selected: _selected.any((e) => e.name == tag.name),
                            onTap: () => _toggle(tag),
                          ),
                        if (!_adding)
                          ListRow(
                            title: l10n.addEvent,
                            leading: const Icon(Symbols.add_rounded),
                            chevron: false,
                            onTap: _startAdding,
                          )
                        else ...[
                          Padding(
                            padding: const EdgeInsets.all(Space.s),
                            child: TextField(
                              controller: _name,
                              autofocus: true,
                              textInputAction: TextInputAction.done,
                              decoration: InputDecoration(hintText: l10n.eventName),
                              onSubmitted: (_) => _addTyped(),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xs),
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
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
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
