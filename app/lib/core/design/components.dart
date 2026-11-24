/// The component library. Screens build from these instead of raw Material
/// widgets so the rules in docs/design-principles.md hold everywhere.
library;

import 'dart:async';

import 'package:flutter/cupertino.dart'
    show
        CupertinoActionSheet,
        CupertinoActionSheetAction,
        CupertinoAlertDialog,
        CupertinoDialogAction,
        CupertinoTextField,
        showCupertinoModalPopup;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import 'balanced_text.dart';
import 'tokens.dart';

export 'balanced_text.dart';

/// The one primary action of a screen.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.hangIcon = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;

  /// Shows a spinner and ignores taps while the action runs.
  final bool busy;

  /// Centers the label alone, [icon] hung before it: the words line up
  /// with centered lines above and below (an empty state's).
  final bool hangIcon;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final child = busy
        ? SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: c.onAccent,
            ),
          )
        : Text(label, textAlign: TextAlign.center);
    final i = icon;
    final button = i == null || busy
        ? FilledButton(onPressed: busy ? () {} : onPressed, child: child)
        : hangIcon
        ? FilledButton(
            onPressed: onPressed,
            // As wide again after the label, unseen, so the label is centered.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                i,
                const SizedBox(width: Space.s),
                Flexible(child: child),
                const SizedBox(width: Space.s),
                Visibility.maintain(visible: false, child: i),
              ],
            ),
          )
        : FilledButton.icon(onPressed: onPressed, icon: i, label: child);
    // While busy the label is a spinner; keep the name for screen readers
    // without adding a second button node.
    return busy ? Semantics(label: label, excludeSemantics: true, button: true, child: button) : button;
  }
}

/// A secondary action: plain accent text, full width when [expand].
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.expand = false,
    this.destructive = false,
    this.icon,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool expand;
  final bool destructive;
  final Widget? icon;

  /// Shows a spinner and ignores taps while the action runs.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final style = TextButton.styleFrom(
      foregroundColor: destructive ? c.destructive : c.accent,
      minimumSize: Size(expand ? double.infinity : 48, 50),
    );
    if (busy) {
      // The name kept for screen readers, as PrimaryButton's.
      return Semantics(
        label: label,
        excludeSemantics: true,
        button: true,
        child: TextButton(
          onPressed: () {},
          style: style,
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: destructive ? c.destructive : c.accent),
          ),
        ),
      );
    }
    return icon == null
        ? TextButton(
            onPressed: onPressed,
            style: style,
            child: Text(label, textAlign: TextAlign.center),
          )
        : TextButton.icon(
            onPressed: onPressed,
            style: style,
            icon: icon!,
            label: Text(label),
          );
  }
}

/// A text field's count toward its maxLength, only once it is near: an
/// empty 0/200 under every field is text nobody needs. For buildCounter.
Widget? nearLimitCounter(
  BuildContext context, {
  required int currentLength,
  required bool isFocused,
  required int? maxLength,
}) {
  if (maxLength == null || currentLength < maxLength * 0.8) return null;
  return Text(
    '$currentLength/$maxLength',
    style: AppText.footnote.copyWith(color: AppColors.of(context).secondaryLabel),
  );
}

/// A small action beside a row's text, e.g. 加為同工: neutral, since the
/// accent is for a page's main action and for state. [semanticsLabel] is
/// read out instead of [label] when the label alone does not say whom it
/// acts on.
class RowButton extends StatelessWidget {
  const RowButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.semanticsLabel,
    this.prominent = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? semanticsLabel;

  /// In the accent color: the answer most give, beside one in gray (接受
  /// beside 不要).
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: prominent ? c.onAccent : c.label,
        backgroundColor: prominent ? c.accent : c.fill,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: Space.m),
      ),
      child: Semantics(
        label: semanticsLabel,
        excludeSemantics: semanticsLabel != null,
        child: Text(label),
      ),
    );
  }
}

/// A grouped list section with an optional header and footer, inset with
/// rounded corners like iOS Settings. [headerAction], e.g. 編輯, sits at
/// the header's end, as iOS Health has it over 釘選; only with [header].
class ListSection extends StatelessWidget {
  const ListSection({
    super.key,
    this.header,
    this.headerAction,
    this.footer,
    this.footerLinks = const [],
    required this.children,
  });

  final String? header;
  final ({String label, VoidCallback onPressed})? headerAction;
  final String? footer;

  /// Links in the footer's small words, after [footer]: pages the section
  /// must point to but nobody comes for (a subscription's terms).
  final List<({String label, VoidCallback onPressed})> footerLinks;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(_RowDivider(over: children[i]));
      rows.add(children[i]);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null) _SectionHeader(header!, action: headerAction),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.m),
            child: Material(
              color: c.surface,
              child: Column(children: rows),
            ),
          ),
          if (footer != null) _SectionFooter(footer!),
          if (footerLinks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, 0),
              child: FootnoteLinks(footerLinks),
            ),
        ],
      ),
    );
  }
}

/// How far a row's text starts past its leading widget, so the divider
/// above it starts there too.
double _leadingInset(Widget row) => switch (row) {
  ListRow(leading: IconTile()) => IconTile.size + Space.m,
  ListRow(leading: Avatar()) => Avatar.size + Space.m,
  ListRow(leading: DateBlock()) => DateBlock.minWidth + Space.m,
  // In place of a DateBlock: a day's second event, under its first.
  ListRow(leading: SizedBox(:final width?)) => width + Space.m,
  ListRow(leading: Icon()) => 22 + Space.m,
  _ => 0,
};

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text, {this.action});

  final String text;
  final ({String label, VoidCallback onPressed})? action;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final title = Semantics(
      header: true,
      child: BalancedText(
        text,
        textAlign: TextAlign.start,
        style: AppText.footnote.copyWith(color: c.secondaryLabel),
      ),
    );
    final action = this.action;
    if (action == null) {
      return Padding(padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.s), child: title);
    }
    // The button's own padding makes up the header's at the end, so its
    // text lines up with the rows' values.
    return Padding(
      padding: const EdgeInsets.only(left: Space.m),
      child: Row(
        children: [
          Expanded(child: title),
          TextButton(
            onPressed: action.onPressed,
            style: TextButton.styleFrom(
              foregroundColor: c.accent,
              textStyle: AppText.subheadline,
              padding: const EdgeInsets.symmetric(horizontal: Space.m),
            ),
            child: Text(action.label),
          ),
        ],
      ),
    );
  }
}

class _SectionFooter extends StatelessWidget {
  const _SectionFooter(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 0),
    child: BalancedText(
      text,
      textAlign: TextAlign.start,
      style: AppText.footnote.copyWith(color: AppColors.of(context).secondaryLabel),
    ),
  );
}

/// Links as small as a footnote, in a line, 「服務條款 · 隱私權政策」: under a
/// section, or under a field's footnote.
class FootnoteLinks extends StatelessWidget {
  const FootnoteLinks(this.links, {super.key});

  final List<({String label, VoidCallback onPressed})> links;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final style = AppText.footnote.copyWith(color: c.secondaryLabel);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (i, link) in links.indexed) ...[
            if (i > 0) Text(L10n.of(context).dotSeparator, style: style),
            // Tall enough to tap, the words as small as the footer's.
            InkWell(
              onTap: link.onPressed,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: Space.minTap(Theme.of(context).platform)),
                child: Align(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Text(link.label, style: style.copyWith(color: c.accent)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The line over the row [over]: under its text, as iOS draws it, when it
/// has a leading.
class _RowDivider extends StatelessWidget {
  const _RowDivider({required this.over});

  final Widget over;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.only(start: Space.m + _leadingInset(over)),
    child: Divider(height: 0.5, thickness: 0.5, color: AppColors.of(context).separator),
  );
}

/// A [ListSection] whose rows are put in order by holding one and dragging
/// it, with no handle beside the chevron (2026-11-20). A sliver, so a row
/// dragged past the screen's edge scrolls the page. [after] are fixed rows
/// below them (新增…). The new order shows until [onReorder]'s write is
/// done; then [items] again, saved or not.
class ReorderableSection<T> extends StatefulWidget {
  const ReorderableSection({
    super.key,
    this.header,
    this.footer,
    required this.items,
    required this.keyOf,
    required this.row,
    required this.onReorder,
    this.after = const [],
  });

  final String? header;
  final String? footer;
  final List<T> items;
  final Object Function(T item) keyOf;

  /// The row for one item.
  final Widget Function(T item) row;
  final Future<void> Function(List<T> next) onReorder;
  final List<Widget> after;

  @override
  State<ReorderableSection<T>> createState() => _ReorderableSectionState<T>();
}

class _ReorderableSectionState<T> extends State<ReorderableSection<T>> {
  List<T>? _moved;

  Future<void> _reorder(int from, int to) async {
    final next = [...(_moved ?? widget.items)];
    next.insert(to > from ? to - 1 : to, next.removeAt(from));
    Haptics.selection();
    setState(() => _moved = next);
    try {
      await widget.onReorder(next);
    } finally {
      if (mounted) setState(() => _moved = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final items = _moved ?? widget.items;
    const corner = Radius.circular(Radii.m);
    // Each row paints its own part of the card, rounded at its ends.
    BorderRadius ends({required bool first, required bool last}) =>
        BorderRadius.vertical(top: first ? corner : Radius.zero, bottom: last ? corner : Radius.zero);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.m),
      sliver: SliverMainAxisGroup(
        slivers: [
          if (widget.header != null) SliverToBoxAdapter(child: _SectionHeader(widget.header!)),
          SliverReorderableList(
            itemCount: items.length,
            onReorder: _reorder,
            itemBuilder: (_, i) {
              final row = widget.row(items[i]);
              return Material(
                key: ValueKey(widget.keyOf(items[i])),
                color: c.surface,
                borderRadius: ends(first: i == 0, last: i == items.length - 1 && widget.after.isEmpty),
                clipBehavior: Clip.antiAlias,
                child: ReorderableDelayedDragStartListener(
                  index: i,
                  enabled: items.length > 1,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (i > 0) _RowDivider(over: row),
                      row,
                    ],
                  ),
                ),
              );
            },
          ),
          if (widget.after.isNotEmpty)
            SliverToBoxAdapter(
              child: Material(
                color: c.surface,
                borderRadius: ends(first: items.isEmpty, last: true),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, row) in widget.after.indexed) ...[
                      if (i > 0 || items.isNotEmpty) _RowDivider(over: row),
                      row,
                    ],
                  ],
                ),
              ),
            ),
          if (widget.footer != null) SliverToBoxAdapter(child: _SectionFooter(widget.footer!)),
        ],
      ),
    );
  }
}

/// One row in a [ListSection].
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.value,
    this.onTap,
    this.chevron,
    this.destructive = false,
    this.tinted = false,
    this.dimmed = false,
    this.selected,
    this.subtitleLines,
    this.subtitleAlert = false,
  });

  final String title;
  final String? subtitle;

  /// [subtitle] in the destructive color: something on the row to fix.
  final bool subtitleAlert;

  /// At most this many lines of [subtitle], the rest cut with an
  /// ellipsis: a long address in a list, whole on the page it opens.
  final int? subtitleLines;
  final Widget? leading;
  final Widget? trailing;

  /// Short text on the trailing side, e.g. the current setting.
  final String? value;
  final VoidCallback? onTap;

  /// Shows a disclosure chevron. Defaults to true when [onTap] is set and
  /// there is no [trailing] widget.
  final bool? chevron;
  final bool destructive;

  /// An action done at once, such as 複製活動: the title in the accent
  /// color and no chevron, which would say another page opens.
  final bool tinted;

  /// Greys the title, for a row that counts for less than those around it,
  /// such as a meeting that did not happen.
  final bool dimmed;

  /// Non-null makes this a choice row: a check mark when true, and never a
  /// disclosure chevron, since choosing does not open another page.
  final bool? selected;

  static bool _fitsOneLine(BuildContext context, String text, TextStyle style, TextScaler textScaler, double width) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(style)),
      textDirection: Directionality.of(context),
      textScaler: textScaler,
      maxLines: 1,
    )..layout(maxWidth: width);
    try {
      return !painter.didExceedMaxLines;
    } finally {
      painter.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final platform = Theme.of(context).platform;
    final showChevron = chevron ?? (onTap != null && trailing == null && selected == null && !destructive && !tinted);
    final textScaler = MediaQuery.textScalerOf(context);
    final valueStyle = AppText.body.copyWith(color: c.secondaryLabel);
    final subtitleStyle = AppText.subheadline.copyWith(color: subtitleAlert ? c.destructive : c.secondaryLabel);
    final row = InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: Space.minTap(platform)),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.m,
            vertical: 11,
          ),
          child: LayoutBuilder(
            builder: (context, box) {
              // A value beside the title gets at most half the row. One that
              // needs more (large text, a longer language's) goes under the
              // title, whole: wrapped beside it, it reads as two values.
              final stacked = value != null && !_fitsOneLine(context, value!, valueStyle, textScaler, box.maxWidth / 2);
              return Row(
                children: [
                  if (leading != null) ...[
                    // Neutral: the accent is for actions and status, and the
                    // row already says what it is.
                    IconTheme.merge(
                      data: IconThemeData(
                        color: destructive ? c.destructive : c.secondaryLabel,
                        size: 22,
                      ),
                      child: leading!,
                    ),
                    const SizedBox(width: Space.m),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Balanced: when a row's text takes two lines, they
                        // break at a phrase, not one word short.
                        BalancedText(
                          title,
                          textAlign: TextAlign.start,
                          style: AppText.body.copyWith(
                            color: destructive
                                ? c.destructive
                                : tinted
                                ? c.accent
                                : dimmed
                                ? c.secondaryLabel
                                : c.label,
                          ),
                        ),
                        if (stacked)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: BalancedText(value!, textAlign: TextAlign.start, style: valueStyle),
                          ),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: subtitleLines == null
                                ? BalancedText(
                                    subtitle!,
                                    textAlign: TextAlign.start,
                                    style: subtitleStyle,
                                  )
                                : Text(
                                    subtitle!,
                                    maxLines: subtitleLines,
                                    overflow: TextOverflow.ellipsis,
                                    style: subtitleStyle,
                                  ),
                          ),
                      ],
                    ),
                  ),
                  if (value != null && !stacked)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: Space.s),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: box.maxWidth / 2),
                        child: Text(value!, textAlign: TextAlign.end, maxLines: 1, style: valueStyle),
                      ),
                    ),
                  if (trailing != null)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: Space.s),
                      child: trailing!,
                    ),
                  if (selected == true)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: Space.s),
                      child: Icon(
                        Symbols.check_rounded,
                        color: c.accent,
                        size: 22,
                        semanticLabel: L10n.of(context).selected,
                      ),
                    ),
                  if (showChevron)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: Space.xs),
                      child: Icon(
                        Symbols.chevron_right_rounded,
                        color: c.tertiaryLabel,
                        size: 22,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
    return selected == null ? row : Semantics(selected: selected, child: row);
  }
}

/// A row with an adaptive switch; the whole row toggles.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: ListRow(
        title: title,
        subtitle: subtitle,
        leading: leading,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        // As tall as a line of the title, the switch overflowing into the
        // row's padding: a row with a switch is as tall as any other. The
        // whole row toggles, so its tap target is the row's.
        trailing: SizedBox(
          height: 22,
          child: OverflowBox(
            maxHeight: double.infinity,
            fit: OverflowBoxFit.deferToChild,
            child: Switch.adaptive(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ),
    );
  }
}

/// A row whose value is any of [options], ticked in a sheet that opens
/// from it and stays open while they are ticked, 完成 closing it; the row
/// shows those ticked, or [none]. A tick shows at once; one that did not
/// save ([onChanged] false) goes back.
///
/// A sheet, as a selection list in Apple's Settings: Material's menu grew
/// from the row's corner, cramped once a service had a dozen duties.
class MultiSelectRow<T> extends StatefulWidget {
  const MultiSelectRow({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
    required this.label,
    required this.none,
    required this.onChanged,
    this.valueBelow = false,
  });

  final String title;
  final List<T> options;
  final Set<T> selected;
  final String Function(T option) label;
  final String none;
  final Future<bool> Function(T option, bool on) onChanged;

  /// Those ticked always under the title, for a list that often runs long:
  /// beside it when short and under it when long, rows of one page read
  /// from either side.
  final bool valueBelow;

  @override
  State<MultiSelectRow<T>> createState() => _MultiSelectRowState<T>();
}

class _MultiSelectRowState<T> extends State<MultiSelectRow<T>> {
  /// Ticks not yet in [MultiSelectRow.selected]: saving, or saved and on
  /// their way back.
  final _ticking = <T, bool>{};

  /// Tells the open sheet what it shows changed. Not disposed: the sheet
  /// may outlast the row (its section gone meanwhile) and still listen.
  final _changed = ValueNotifier(0);

  @override
  void didUpdateWidget(MultiSelectRow<T> old) {
    super.didUpdateWidget(old);
    _ticking.removeWhere((option, on) => widget.selected.contains(option) == on);
    // Saved elsewhere meanwhile, or come back from the server: the sheet
    // shows it too, after this frame's build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed.value++);
  }

  bool _ticked(T option) => _ticking[option] ?? widget.selected.contains(option);

  Future<void> _tick(T option, bool on) async {
    // Its section gone while the sheet was open: nothing left to tick.
    if (!mounted) return;
    Haptics.selection();
    _set(() => _ticking[option] = on);
    final saved = await widget.onChanged(option, on);
    if (!saved) _set(() => _ticking.remove(option));
  }

  void _set(VoidCallback change) {
    if (!mounted) return;
    setState(change);
    _changed.value++;
  }

  Future<void> _open() => showAppSheet<void>(
    context,
    expand: widget.options.length > _listSheetFits,
    builder: (context) => _ListSheet(
      title: widget.title,
      done: true,
      rows: ValueListenableBuilder(
        valueListenable: _changed,
        builder: (context, _, _) => ListSection(
          children: [
            for (final o in widget.options)
              ListRow(title: widget.label(o), selected: _ticked(o), onTap: () => _tick(o, !_ticked(o))),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ticked = [
      for (final o in widget.options)
        if (_ticked(o)) widget.label(o),
    ];
    final shown = ticked.isEmpty ? widget.none : ticked.join(L10n.of(context).listSeparator);
    return ListRow(
      title: widget.title,
      value: widget.valueBelow ? null : shown,
      subtitle: widget.valueBelow ? shown : null,
      trailing: Icon(Symbols.unfold_more_rounded, color: AppColors.of(context).tertiaryLabel, size: 20),
      onTap: _open,
    );
  }
}

/// A row that opens a sheet of [options], one to pick, which closes it:
/// e.g. 加入聚會.
class MenuRow<T extends Object> extends StatelessWidget {
  const MenuRow({
    super.key,
    required this.title,
    this.leading,
    required this.options,
    required this.label,
    required this.onPicked,
  });

  final String title;
  final Widget? leading;
  final List<T> options;
  final String Function(T option) label;
  final ValueChanged<T> onPicked;

  Future<void> _open(BuildContext context) async {
    final picked = await showAppSheet<T>(
      context,
      expand: options.length > _listSheetFits,
      builder: (context) => _ListSheet(
        title: title,
        rows: ListSection(
          children: [
            for (final o in options) ListRow(title: label(o), chevron: false, onTap: () => Navigator.pop(context, o)),
          ],
        ),
      ),
    );
    if (picked != null) onPicked(picked);
  }

  @override
  Widget build(BuildContext context) =>
      ListRow(title: title, leading: leading, chevron: false, onTap: () => _open(context));
}

/// Options a list sheet shows without being as tall as a sheet gets.
const _listSheetFits = 8;

/// A sheet of options under [title]: with [done], ticked ones saved at
/// once and 完成 to close; without, a pick closes it. Nothing to discard
/// either way, so no 取消; swiping down closes it too.
class _ListSheet extends StatelessWidget {
  const _ListSheet({required this.title, required this.rows, this.done = false});

  final String title;
  final Widget rows;
  final bool done;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetBar(
          title: title,
          cancel: false,
          actions: [
            if (done) SecondaryButton(label: L10n.of(context).done, onPressed: () => Navigator.pop(context)),
          ],
        ),
        Flexible(
          child: ListView(shrinkWrap: true, children: [rows]),
        ),
      ],
    ),
  );
}

/// One sentence and at most one button, inviting the next step; above
/// them, an [icon] for what would be here.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 48, weight: 300, color: c.tertiaryLabel),
              const SizedBox(height: Space.s),
            ],
            BalancedText(message, style: AppText.body.copyWith(color: c.secondaryLabel)),
            if (actionLabel != null) ...[
              const SizedBox(height: Space.s),
              SecondaryButton(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

/// A short message near the bottom; with [onUndo], an 「復原」 action, or
/// with [onRetry] (a failed save), 「重試」. At most one action.
///
/// Used instead of a confirmation dialog for anything that can be undone.
void showToast(
  BuildContext context,
  String message, {
  FutureOr<void> Function()? onUndo,
  VoidCallback? onRetry,
  ({String label, VoidCallback onPressed})? action,
  Duration duration = const Duration(seconds: 5),
}) {
  assert([onUndo, onRetry, action].nonNulls.length <= 1, 'a toast has at most one action');
  final messenger = ScaffoldMessenger.of(context);
  final l10n = L10n.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: BalancedText(message, textAlign: TextAlign.start),
      duration: duration,
      persist: false,
      action: action != null
          ? SnackBarAction(label: action.label, onPressed: action.onPressed)
          : onRetry != null
          ? SnackBarAction(label: l10n.retry, onPressed: onRetry)
          : onUndo == null
          ? null
          : SnackBarAction(
              label: l10n.undo,
              onPressed: () async {
                Haptics.light();
                try {
                  await onUndo();
                  await Future<void>.value();
                  if (!messenger.mounted) return;
                  messenger.hideCurrentSnackBar();
                  messenger.showSnackBar(SnackBar(content: BalancedText(l10n.undoDone, textAlign: TextAlign.start)));
                } catch (_) {
                  // The action itself closes its snackbar, including when a
                  // synchronous refusal happens before the first await.
                  await Future<void>.value();
                  if (!messenger.mounted) return;
                  messenger.hideCurrentSnackBar();
                  messenger.showSnackBar(SnackBar(content: BalancedText(l10n.undoFailed, textAlign: TextAlign.start)));
                }
              },
            ),
    ),
  );
}

/// Runs [commit] after the undo window closes unless the user taps 「復原」.
///
/// For changes the backend cannot reverse (removing a member: only a Cloud
/// Function can add one back), the screen hides the item at once and the
/// write waits. [onUndo] puts the item back on screen.
void showDeferredUndo(
  BuildContext context,
  String message, {
  required Future<void> Function() commit,
  required VoidCallback onUndo,
  void Function(Object error)? onError,
  Duration window = const Duration(seconds: 5),
}) {
  var undone = false;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = L10n.of(context);
  messenger.hideCurrentSnackBar();
  final controller = messenger.showSnackBar(
    SnackBar(
      content: BalancedText(message, textAlign: TextAlign.start),
      duration: window,
      persist: false,
      action: SnackBarAction(
        label: l10n.undo,
        onPressed: () {
          undone = true;
          Haptics.light();
          onUndo();
        },
      ),
    ),
  );
  unawaited(
    controller.closed.then((_) async {
      if (undone) return;
      try {
        await commit();
      } catch (e) {
        onUndo();
        onError?.call(e);
      }
    }),
  );
}

/// A confirmation for actions the user cannot undo themselves: leaving a
/// church, deleting an account or a church, discarding a sheet's unsaved
/// changes. Returns true to go ahead.
///
/// Platform style (Cupertino alert on iOS), with 「取消」 (or [cancel]) and a
/// red action named for what happens.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  String? message,
  required String action,
  String? cancel,
}) async {
  final l10n = L10n.of(context);
  final result = await showAdaptiveDialog<bool>(
    context: context,
    builder: (context) {
      final c = AppColors.of(context);
      final ios = Theme.of(context).platform == TargetPlatform.iOS;
      return AlertDialog.adaptive(
        title: Text(title),
        content: message == null ? null : _dialogMessage(message, ios: ios),
        actions: [
          _dialogAction(
            context,
            ios,
            cancel ?? l10n.cancel,
            () => Navigator.pop(context, false),
          ),
          _dialogAction(
            context,
            ios,
            action,
            () => Navigator.pop(context, true),
            color: c.destructive,
            destructive: true,
          ),
        ],
      );
    },
  );
  if (result == true) Haptics.heavy();
  return result ?? false;
}

/// A dialog's message: centered on iPhone, as its own alerts are; at the
/// start on Android, as Material's (2026-11-23: start everywhere since
/// 10/18 read oddly on iPhone).
Widget _dialogMessage(String message, {required bool ios}) =>
    BalancedText(message, textAlign: ios ? TextAlign.center : TextAlign.start);

/// A dialog that just asks one question with two answers, e.g. whether to
/// also add a duty to someone. Returns true for [yes].
Future<bool?> askChoice(
  BuildContext context, {
  required String title,
  String? message,
  required String yes,
  required String no,
}) {
  return showAdaptiveDialog<bool>(
    context: context,
    builder: (context) {
      final ios = Theme.of(context).platform == TargetPlatform.iOS;
      return AlertDialog.adaptive(
        title: Text(title),
        content: message == null ? null : _dialogMessage(message, ios: ios),
        actions: [
          _dialogAction(context, ios, no, () => Navigator.pop(context, false)),
          _dialogAction(
            context,
            ios,
            yes,
            () => Navigator.pop(context, true),
            defaultAction: true,
          ),
        ],
      );
    },
  );
}

/// Asks for a line of text. Null when cancelled or empty; with
/// [optional], empty is an answer and only cancelling is null. The action
/// is [action], or 「儲存」. [helper] says something under the field about
/// what is typed so far; [error], what keeps it from being saved, said as
/// it is typed and holding the action back (a name someone has). Platform
/// style, as the other dialogs: on iPhone, Apple's alert with a text field.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? label,
  String? hint,
  String initial = '',
  int? maxLength,
  int maxLines = 1,
  String? action,
  bool optional = false,
  String? Function(String text)? helper,
  String? Function(String text)? error,
}) async {
  final result = await showAdaptiveDialog<String>(
    context: context,
    builder: (context) => _PromptDialog(
      title: title,
      label: label,
      hint: hint,
      initial: initial,
      maxLength: maxLength,
      maxLines: maxLines,
      action: action,
      helper: helper,
      error: error,
    ),
  );
  final t = result?.trim();
  return t == null || (t.isEmpty && !optional) ? null : t;
}

/// Owns its text controller, so the controller outlives the closing
/// animation.
class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    this.label,
    this.hint,
    required this.initial,
    this.maxLength,
    required this.maxLines,
    this.action,
    this.helper,
    this.error,
  });

  final String title;
  final String? label;
  final String? hint;
  final String initial;
  final int? maxLength;
  final int maxLines;
  final String? action;
  final String? Function(String text)? helper;
  final String? Function(String text)? error;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final _controller = TextEditingController(text: widget.initial)
    ..addListener(() {
      if (widget.helper != null || widget.error != null) setState(() {});
    });

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final oneLine = widget.maxLines == 1;
    final error = widget.error?.call(_controller.text);
    final helper = error == null ? widget.helper?.call(_controller.text) : null;
    void submit(String v) {
      if (error == null) Navigator.pop(context, v);
    }

    if (Theme.of(context).platform == TargetPlatform.iOS) {
      final c = AppColors.of(context);
      return CupertinoAlertDialog(
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.label case final label?) Text(label),
            const SizedBox(height: Space.s),
            CupertinoTextField(
              controller: _controller,
              autofocus: true,
              maxLength: widget.maxLength,
              minLines: 1,
              maxLines: widget.maxLines,
              placeholder: widget.hint,
              textInputAction: oneLine ? TextInputAction.done : null,
              onSubmitted: oneLine ? submit : null,
            ),
            if (error ?? helper case final said?)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: BalancedText(
                  said,
                  style: AppText.footnote.copyWith(color: error != null ? c.destructive : c.secondaryLabel),
                ),
              ),
          ],
        ),
        actions: [
          _dialogAction(context, true, l10n.cancel, () => Navigator.pop(context)),
          _dialogAction(
            context,
            true,
            widget.action ?? l10n.save,
            error == null ? () => submit(_controller.text) : null,
            defaultAction: true,
          ),
        ],
      );
    }
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: widget.maxLength,
        buildCounter: nearLimitCounter,
        minLines: 1,
        maxLines: widget.maxLines,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          helperText: helper,
          helperMaxLines: 3,
          errorText: error,
          errorMaxLines: 3,
        ),
        onSubmitted: oneLine ? submit : null,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        TextButton(
          onPressed: error == null ? () => submit(_controller.text) : null,
          child: Text(widget.action ?? l10n.save),
        ),
      ],
    );
  }
}

Widget _dialogAction(
  BuildContext context,
  bool ios,
  String label,
  VoidCallback? onPressed, {
  Color? color,
  bool destructive = false,
  bool defaultAction = false,
}) {
  if (ios) {
    return CupertinoDialogAction(
      onPressed: onPressed,
      isDestructiveAction: destructive,
      isDefaultAction: defaultAction,
      child: Text(label),
    );
  }
  return TextButton(
    onPressed: onPressed,
    style: color == null ? null : TextButton.styleFrom(foregroundColor: color),
    child: Text(label),
  );
}

/// Opens a bottom sheet with a grab handle that the user can drag down to
/// close. The keyboard goes first: left up, it covered the sheet, and came
/// back over the page once the sheet closed.
///
/// [expand] makes it as tall as a sheet gets; others are as tall as their
/// content, up to that, so the page behind still shows above every sheet.
/// A sheet with a form says so with [UnsavedChanges].
Future<T?> showAppSheet<T>(BuildContext context, {required WidgetBuilder builder, bool expand = false}) {
  FocusManager.instance.primaryFocus?.unfocus();
  // Over the tab bar too, like a system sheet; the tab navigator alone
  // left the bar bright and tappable below the dimmed page.
  final navigator = Navigator.of(context, rootNavigator: true);
  final localizations = MaterialLocalizations.of(context);
  // As showModalBottomSheet has it, with a route that can ask.
  return navigator.push(
    _AppSheetRoute<T>(
      builder: (context) => LayoutBuilder(
        builder: (context, box) {
          final tallest = box.maxHeight * _sheetHeight;
          return expand
              ? SizedBox(height: tallest, child: builder(context))
              : ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: tallest),
                  child: builder(context),
                );
        },
      ),
      capturedThemes: InheritedTheme.capture(from: context, to: navigator.context),
      isScrollControlled: true,
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(localizations.bottomSheetLabel),
      modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
      showDragHandle: true,
      useSafeArea: true,
    ),
  );
}

/// The most of the screen a sheet takes, as an iPhone's tallest sheet.
const _sheetHeight = 0.92;

/// In a sheet from [showAppSheet], says whether it has changes its 完成 (or
/// 儲存) would keep. While [changed] says so, closing it any other way
/// (swiped down, tapped outside, back, its 取消) asks first whether to
/// discard them, as Apple's sheets do.
class UnsavedChanges extends StatelessWidget {
  const UnsavedChanges({super.key, required this.changed, required this.child});

  /// Asked as the sheet is closing, so it need not rebuild as text is typed.
  final bool Function() changed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    assert(route is _AppSheetRoute, 'UnsavedChanges is for a sheet opened with showAppSheet');
    if (route is _AppSheetRoute) route.changed = changed;
    return child;
  }
}

/// showAppSheet's route. Every way of closing a sheet without a result
/// comes through [didPop], a swipe too (it pops past any PopScope), so it
/// is where unsaved changes stop it.
class _AppSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _AppSheetRoute({
    required super.builder,
    super.capturedThemes,
    required super.isScrollControlled,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.modalBarrierColor,
    super.showDragHandle,
    super.useSafeArea,
  });

  /// Set by the sheet's [UnsavedChanges].
  bool Function()? changed;
  bool _discarding = false;

  @override
  bool didPop(T? result) {
    if (result == null && !_discarding && !willHandlePopInternally && (changed?.call() ?? false)) {
      // Back up, if a swipe had it on its way down; asked once the
      // navigator is done popping.
      controller?.forward();
      scheduleMicrotask(_askToDiscard);
      return false;
    }
    return super.didPop(result);
  }

  Future<void> _askToDiscard() async {
    final context = subtreeContext;
    if (context == null || !isActive) return;
    if (!await _confirmDiscard(context) || !isCurrent) return;
    _discarding = true;
    navigator?.pop();
  }
}

/// Asks before something that cannot be taken back but destroys nothing,
/// such as sending a push to many (通知同工填, #91): on iPhone from below, as
/// [_confirmDiscard] asks, elsewhere as a dialog. True to go ahead.
/// [destructive]: [action] in red, as 沒有聚會, which takes everyone off.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  String? message,
  required String action,
  required String cancel,
  bool destructive = false,
}) async {
  if (Theme.of(context).platform != TargetPlatform.iOS) {
    if (destructive) {
      return confirmDestructive(context, title: title, message: message, action: action, cancel: cancel);
    }
    return await askChoice(context, title: title, message: message, yes: action, no: cancel) ?? false;
  }
  return _askFromBelow(
    context,
    title: title,
    message: message,
    action: action,
    cancel: cancel,
    destructive: destructive,
  );
}

/// Asks whether to discard a page's unsaved changes (安排服事), as a sheet's
/// are asked. True to discard them.
Future<bool> confirmDiscard(BuildContext context) => _confirmDiscard(context);

/// Asks whether to discard a sheet's unsaved changes: on iPhone from below,
/// as Apple's sheets ask (an action sheet), elsewhere as a dialog. True to
/// discard them.
Future<bool> _confirmDiscard(BuildContext context) async {
  final l10n = L10n.of(context);
  if (Theme.of(context).platform != TargetPlatform.iOS) {
    return confirmDestructive(
      context,
      title: l10n.discardChangesTitle,
      action: l10n.discardChanges,
      cancel: l10n.keepEditing,
    );
  }
  final discard = await _askFromBelow(
    context,
    title: l10n.discardChangesTitle,
    action: l10n.discardChanges,
    cancel: l10n.keepEditing,
    destructive: true,
  );
  if (discard) Haptics.heavy();
  return discard;
}

/// iOS's action sheet with one [action] and [cancel]: true for [action].
Future<bool> _askFromBelow(
  BuildContext context, {
  required String title,
  String? message,
  required String action,
  required String cancel,
  bool destructive = false,
}) async {
  final result = await showCupertinoModalPopup<bool>(
    context: context,
    builder: (context) => CupertinoActionSheet(
      title: Text(title),
      message: message == null ? null : Text(message),
      actions: [
        CupertinoActionSheetAction(
          isDestructiveAction: destructive,
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(context, false),
        child: Text(cancel),
      ),
    ),
  );
  return result ?? false;
}

/// Apple's sheet bar: 取消 leading (without [cancel]: nothing), [title] in
/// the middle, [actions] trailing, the last the one that keeps what was
/// done (完成, 儲存). Every sheet with a form or a choice to confirm has one.
class SheetBar extends StatelessWidget {
  const SheetBar({super.key, required this.title, this.cancel = true, required this.actions});

  final String title;
  final bool cancel;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s, 0, Space.s, Space.s),
      // As tall as its buttons.
      child: SizedBox(
        height: 50,
        child: NavigationToolbar(
          leading: cancel
              ? SecondaryButton(label: L10n.of(context).cancel, onPressed: () => Navigator.pop(context))
              : null,
          middle: Text(title, style: AppText.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: actions),
          middleSpacing: Space.s,
        ),
      ),
    );
  }
}

/// Asks for a day between [first] and [last]: a month in a sheet, where one
/// tap picks it. Not Material's date dialog, which wants 確定 after the day
/// and offers typing it, and 10/18/2026 reads the other way in some places.
Future<DateTime?> pickDay(
  BuildContext context, {
  required String title,
  required DateTime initial,
  required DateTime first,
  required DateTime last,
}) {
  return showAppSheet<DateTime>(
    context,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.m),
              child: Text(title, style: AppText.title3),
            ),
            DayCalendar(
              initial: initial.isBefore(first) ? first : (initial.isAfter(last) ? last : initial),
              first: first,
              last: last,
              onPicked: (day) => Navigator.pop(context, day),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A month where a tap on a day picks it. Picking a year only turns the
/// month to it: Flutter's calendar counts that as picking the same day
/// there, which closed the picker before any day was tapped.
class DayCalendar extends StatefulWidget {
  const DayCalendar({
    super.key,
    required this.initial,
    required this.first,
    required this.last,
    required this.onPicked,
  });

  final DateTime initial;
  final DateTime first;
  final DateTime last;
  final ValueChanged<DateTime> onPicked;

  @override
  State<DayCalendar> createState() => _DayCalendarState();
}

class _DayCalendarState extends State<DayCalendar> {
  /// Set as a year's month turns up, just before the calendar reports its
  /// day as picked; a tapped day turns no month.
  bool _turned = false;

  @override
  Widget build(BuildContext context) => CalendarDatePicker(
    initialDate: widget.initial,
    firstDate: widget.first,
    lastDate: widget.last,
    onDisplayedMonthChanged: (_) {
      _turned = true;
      scheduleMicrotask(() => _turned = false);
    },
    onDateChanged: (day) {
      if (!_turned) widget.onPicked(day);
    },
  );
}

/// A search box. Filled, with a clear button once there is text.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.onChanged,
    this.hint,
    this.autofocus = false,
    this.controller,
  });

  final ValueChanged<String> onChanged;
  final String? hint;
  final bool autofocus;
  final TextEditingController? controller;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final TextEditingController _controller = widget.controller ?? TextEditingController();

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final l10n = L10n.of(context);
    return TextField(
      controller: _controller,
      autofocus: widget.autofocus,
      onChanged: (v) {
        setState(() {});
        widget.onChanged(v);
      },
      textInputAction: TextInputAction.search,
      style: AppText.body,
      decoration: InputDecoration(
        hintText: widget.hint ?? l10n.search,
        prefixIcon: Icon(Symbols.search_rounded, color: c.secondaryLabel),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: l10n.clear,
                icon: Icon(Symbols.cancel_rounded, fill: 1, color: c.tertiaryLabel, size: 20),
                onPressed: () {
                  _controller.clear();
                  setState(() {});
                  widget.onChanged('');
                },
              ),
      ),
    );
  }
}

/// A row swiped toward its start to do one thing, 刪除 unless [label]
/// says otherwise, as iPhone lists do: a short swipe stops with the button
/// showing, done once it is tapped; one past half the row does it on
/// letting go. A tap on the row while open closes it; opening another
/// closes this one. Whatever it does, the row's list decides whether it
/// stays: this springs back.
class SwipeAction extends StatefulWidget {
  const SwipeAction({
    super.key,
    required this.onAction,
    required this.child,
    this.label,
    this.semanticLabel,
    this.enabled = true,
  });

  final VoidCallback onAction;
  final Widget child;

  /// What the swipe does, if not 刪除.
  final String? label;

  /// What a screen reader offers in its place, if not [label].
  final String? semanticLabel;

  /// Off: the row as it is, nothing to swipe.
  final bool enabled;

  @override
  State<SwipeAction> createState() => _SwipeActionState();
}

class _SwipeActionState extends State<SwipeAction> with SingleTickerProviderStateMixin {
  /// The one open now, closed when another opens.
  static _SwipeActionState? _open;

  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  }

  /// How far it has moved toward its start, in logical pixels.
  double get _dx => _ctrl.value * _width;
  double _width = 1;
  double _button = 80;

  @override
  void dispose() {
    if (_open == this) _open = null;
    _ctrl.dispose();
    super.dispose();
  }

  void _to(double dx) {
    final to = (dx / _width).clamp(0.0, 1.0);
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.value = to;
    } else {
      _ctrl.animateTo(to, curve: Curves.easeOutCubic);
    }
    if (dx > 0) {
      if (_open != this) _open?._close();
      _open = this;
    } else if (_open == this) {
      _open = null;
    }
  }

  void _close() => _to(0);

  void _act() {
    _close();
    widget.onAction();
  }

  bool get _rtl => Directionality.of(context) == TextDirection.rtl;

  void _update(DragUpdateDetails d) {
    final toward = _rtl ? d.primaryDelta! : -d.primaryDelta!;
    _ctrl.value = ((_dx + toward) / _width).clamp(0.0, 1.0);
    if (_dx > 0 && _open != this) {
      _open?._close();
      _open = this;
    }
  }

  void _end(DragEndDetails d) {
    final v = _rtl ? d.primaryVelocity ?? 0 : -(d.primaryVelocity ?? 0);
    if (_dx > _width / 2) {
      _act();
    } else if (_dx > _button / 2 || v > 300 && _dx > 0) {
      _to(v < -300 ? 0 : _button);
    } else {
      _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final c = AppColors.of(context);
    final label = widget.label ?? L10n.of(context).delete;
    // Measured as drawn, in the app's font: measured in another, the
    // button came out narrower than the word, and only 刪 showed.
    final style = DefaultTextStyle.of(context).style.merge(AppText.body.copyWith(color: c.onAccent));
    final locale = Localizations.maybeLocaleOf(context);
    return Semantics(
      customSemanticsActions: {CustomSemanticsAction(label: widget.semanticLabel ?? label): widget.onAction},
      child: LayoutBuilder(
        builder: (context, box) {
          _width = box.maxWidth.isFinite && box.maxWidth > 0 ? box.maxWidth : 1;
          final painter = TextPainter(
            text: TextSpan(text: label, style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            locale: locale,
          )..layout();
          _button = (painter.width.ceilToDouble() + Space.l * 2).clamp(80.0, _width / 2);
          painter.dispose();
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: _update,
            onHorizontalDragEnd: _end,
            onHorizontalDragCancel: () => _to(_dx > _button / 2 ? _button : 0),
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, child) {
                final dx = _dx;
                return Stack(
                  children: [
                    // Kept in place when shut, so the row below keeps its state.
                    Positioned.fill(
                      child: dx == 0
                          ? const SizedBox.shrink()
                          : ColoredBox(
                              color: c.destructive,
                              child: Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: SizedBox(
                                  width: dx < _button ? _button : dx,
                                  child: Semantics(
                                    button: true,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: _act,
                                      child: Align(
                                        // Past the button, the word rides at the row's edge.
                                        alignment: dx > _button
                                            ? AlignmentDirectional.centerStart
                                            : AlignmentDirectional.center,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: Space.l),
                                          child: Text(label, style: style, maxLines: 1, softWrap: false),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                    Transform.translate(
                      offset: Offset(_rtl ? dx : -dx, 0),
                      child: Stack(
                        children: [
                          IgnorePointer(ignoring: dx > 0, child: child),
                          if (dx > 0)
                            Positioned.fill(
                              child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _close),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
              child: widget.child,
            ),
          );
        },
      ),
    );
  }
}

/// The name of a 特別活動 color ([EventColors]), or of none: 灰.
String eventColorName(L10n l10n, int? i) => switch (i) {
  null => l10n.colorNameGrey,
  0 => l10n.colorName0,
  1 => l10n.colorName1,
  2 => l10n.colorName2,
  3 => l10n.colorName3,
  4 => l10n.colorName4,
  _ => l10n.colorName5,
};

/// The [EventColors] as a row of dots, the picked one ringed in black;
/// tapped, picked. [grey]: a grey one first, for none (null), as a 行事曆
/// 活動 with no color of its own.
class ColorDots extends StatelessWidget {
  const ColorDots({super.key, required this.selected, required this.onPick, this.grey = false});

  final int? selected;
  final ValueChanged<int?> onPick;
  final bool grey;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Wrap(
      children: [
        if (grey)
          _ColorDot(
            index: null,
            label: eventColorName(l10n, null),
            selected: selected == null,
            onTap: () => onPick(null),
          ),
        for (var i = 0; i < EventColors.count; i++)
          _ColorDot(index: i, label: eventColorName(l10n, i), selected: selected == i, onTap: () => onPick(i)),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.index,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final int? index;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final colors = switch (index) {
      final i? => EventColors.of(context, i),
      null => (bg: c.fill, fg: c.secondaryLabel),
    };
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

/// A name as a title, tapped to rename it: a member's on their page, a
/// 常用特別活動's atop its menu. A small pencil after it, which, where
/// titles are centred, the name is centred without; [centred] says
/// whether, if not as the app bar has it.
class NameTitle extends StatelessWidget {
  const NameTitle({super.key, required this.name, required this.onTap, this.centred});

  final String name;
  final VoidCallback onTap;
  final bool? centred;

  static const _icon = 16.0;
  static const _gap = 4.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final centred =
        this.centred ??
        theme.appBarTheme.centerTitle ??
        switch (theme.platform) {
          TargetPlatform.iOS || TargetPlatform.macOS => true,
          _ => false,
        };
    return Semantics(
      button: true,
      hint: L10n.of(context).rename,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (centred) const SizedBox(width: _icon + _gap),
              Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: _gap),
              ExcludeSemantics(
                child: Icon(Symbols.edit_rounded, size: _icon, color: AppColors.of(context).tertiaryLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small colored label: special events, "my service" badges.
class Tag extends StatelessWidget {
  const Tag({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
  });

  factory Tag.event(BuildContext context, String label, int color) {
    final colors = EventColors.of(context, color);
    return Tag(label: label, background: colors.bg, foreground: colors.fg);
  }

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(Radii.s),
      ),
      child: Text(
        label,
        style: AppText.footnote.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A row's icon, white on a [TileColors] square, as in iOS Settings. Only
/// on 設定, where it groups a long page; elsewhere row icons stay neutral.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, required this.color});

  static const double size = 30;

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(7)),
      // Filled, as iOS Settings draws them: an outline is thin in white.
      child: Icon(icon, size: 20, fill: 1, color: Colors.white),
    );
  }
}

/// A person's first character in a circle, standing in for a photo.
/// Neutral: the accent is for actions and status.
class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key});

  static const double size = 44;

  final String name;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final initial = name.trim().characters.firstOrNull ?? '';
    // Grows with the letter, as text does.
    final size = MediaQuery.textScalerOf(context).scale(Avatar.size);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.fill, shape: BoxShape.circle),
        child: Text(
          initial.toUpperCase(),
          style: AppText.title3.copyWith(color: c.secondaryLabel),
        ),
      ),
    );
  }
}

/// A day as a calendar leaf: the month small, the date large. Today's is
/// filled with the accent. Screen readers hear [semanticLabel], the whole
/// date, instead of the two numbers.
class DateBlock extends StatelessWidget {
  const DateBlock({
    super.key,
    required this.month,
    required this.day,
    required this.today,
    required this.semanticLabel,
    this.past = false,
    this.color,
  });

  static const double minWidth = 48;

  /// The month as the language abbreviates it: 10月, Oct.
  final String month;
  final int day;
  final bool today;
  final String semanticLabel;

  /// A day gone: its number greyed like the month.
  final bool past;

  /// An event's own color, one of [EventColors], its leaf in it; today's
  /// stays the accent.
  final int? color;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final own = switch (color) {
      final i? when !today => EventColors.of(context, i),
      _ => null,
    };
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: DateBlock.minWidth),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: today ? c.accent : own?.bg ?? c.fill,
          borderRadius: BorderRadius.circular(Radii.s),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              month,
              maxLines: 1,
              style: AppText.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: today ? c.onAccent : own?.fg ?? c.secondaryLabel,
                height: 1.1,
              ),
            ),
            Text(
              '$day',
              style: AppText.title3.copyWith(
                fontWeight: FontWeight.w700,
                color: today ? c.onAccent : own?.fg ?? (past ? c.secondaryLabel : c.label),
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section title above full-width rows, e.g. in the people picker. Lines
/// up with the rows' text and reads like a [ListSection] header.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.l, Space.m, Space.s),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: BalancedText(
                text,
                textAlign: TextAlign.start,
                style: AppText.footnote.copyWith(color: c.secondaryLabel),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Inline error with a retry, shown in place of content that failed to
/// load. Says how to fix it, without technical detail.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
    message: message,
    actionLabel: onRetry == null ? null : L10n.of(context).retry,
    onAction: onRetry,
  );
}

/// Haptic feedback on key actions (done, delete), both platforms.
abstract final class Haptics {
  static void light() {
    if (!kIsWeb) HapticFeedback.lightImpact();
  }

  static void success() {
    if (!kIsWeb) HapticFeedback.mediumImpact();
  }

  static void heavy() {
    if (!kIsWeb) HapticFeedback.heavyImpact();
  }

  static void selection() {
    if (!kIsWeb) HapticFeedback.selectionClick();
  }
}
