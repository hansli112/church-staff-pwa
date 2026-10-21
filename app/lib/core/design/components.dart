/// The component library. Screens build from these instead of raw Material
/// widgets so the rules in docs/design-principles.md hold everywhere.
library;

import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoDialogAction;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
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
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;

  /// Shows a spinner and ignores taps while the action runs.
  final bool busy;

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
    final button = icon == null || busy
        ? FilledButton(onPressed: busy ? () {} : onPressed, child: child)
        : FilledButton.icon(onPressed: onPressed, icon: icon!, label: child);
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
  });

  final String label;
  final VoidCallback? onPressed;
  final bool expand;
  final bool destructive;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final style = TextButton.styleFrom(
      foregroundColor: destructive ? c.destructive : c.accent,
      minimumSize: Size(expand ? double.infinity : 48, 50),
    );
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

/// A small action beside a row's text, e.g. 加為同工: neutral, since the
/// accent is for a page's main action and for state. [semanticsLabel] is
/// read out instead of [label] when the label alone does not say whom it
/// acts on.
class RowButton extends StatelessWidget {
  const RowButton({super.key, required this.label, required this.onPressed, this.semanticsLabel});

  final String label;
  final VoidCallback? onPressed;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: c.label,
        backgroundColor: c.fill,
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
/// rounded corners like iOS Settings.
class ListSection extends StatelessWidget {
  const ListSection({
    super.key,
    this.header,
    this.footer,
    required this.children,
  });

  final String? header;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          Padding(
            // Under the text, as iOS draws it, when the row has a leading.
            padding: EdgeInsetsDirectional.only(start: Space.m + _leadingInset(children[i])),
            child: Divider(height: 0.5, thickness: 0.5, color: c.separator),
          ),
        );
      }
      rows.add(children[i]);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.m,
                Space.s,
                Space.m,
                Space.s,
              ),
              child: Semantics(
                header: true,
                child: BalancedText(
                  header!,
                  textAlign: TextAlign.start,
                  style: AppText.footnote.copyWith(color: c.secondaryLabel),
                ),
              ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.m),
            child: Material(
              color: c.surface,
              child: Column(children: rows),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 0),
              child: BalancedText(
                footer!,
                textAlign: TextAlign.start,
                style: AppText.footnote.copyWith(color: c.secondaryLabel),
              ),
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
  ListRow(leading: Icon()) => 22 + Space.m,
  _ => 0,
};

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
    this.selected,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;

  /// Short text on the trailing side, e.g. the current setting.
  final String? value;
  final VoidCallback? onTap;

  /// Shows a disclosure chevron. Defaults to true when [onTap] is set and
  /// there is no [trailing] widget.
  final bool? chevron;
  final bool destructive;

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
    final showChevron = chevron ?? (onTap != null && trailing == null && selected == null && !destructive);
    final textScaler = MediaQuery.textScalerOf(context);
    final valueStyle = AppText.body.copyWith(color: c.secondaryLabel);
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
                            color: destructive ? c.destructive : c.label,
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
                            child: BalancedText(
                              subtitle!,
                              textAlign: TextAlign.start,
                              style: AppText.subheadline.copyWith(
                                color: c.secondaryLabel,
                              ),
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
        trailing: Switch.adaptive(value: value, onChanged: onChanged),
      ),
    );
  }
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
  Duration duration = const Duration(seconds: 5),
}) {
  assert(onUndo == null || onRetry == null, 'a toast has at most one action');
  final messenger = ScaffoldMessenger.of(context);
  final l10n = L10n.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: BalancedText(message, textAlign: TextAlign.start),
      duration: duration,
      persist: false,
      action: onRetry != null
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
/// church, deleting an account or a church. Returns true to go ahead.
///
/// Platform style (Cupertino alert on iOS), with 「取消」 and a red action
/// named for what happens.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  String? message,
  required String action,
}) async {
  final l10n = L10n.of(context);
  final result = await showAdaptiveDialog<bool>(
    context: context,
    builder: (context) {
      final c = AppColors.of(context);
      final ios = Theme.of(context).platform == TargetPlatform.iOS;
      return AlertDialog.adaptive(
        title: Text(title),
        content: message == null ? null : BalancedText(message, textAlign: TextAlign.start),
        actions: [
          _dialogAction(
            context,
            ios,
            l10n.cancel,
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
        content: message == null ? null : BalancedText(message, textAlign: TextAlign.start),
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

Widget _dialogAction(
  BuildContext context,
  bool ios,
  String label,
  VoidCallback onPressed, {
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
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool expand = false,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<T>(
    context: context,
    // Over the tab bar too, like a system sheet; the tab navigator alone
    // left the bar bright and tappable below the dimmed page.
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => expand ? FractionallySizedBox(heightFactor: 0.92, child: builder(context)) : builder(context),
  );
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
  });

  static const double minWidth = 48;

  /// The month as the language abbreviates it: 10月, Oct.
  final String month;
  final int day;
  final bool today;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: DateBlock.minWidth),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: today ? c.accent : c.fill,
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
                color: today ? c.onAccent : c.secondaryLabel,
                height: 1.1,
              ),
            ),
            Text(
              '$day',
              style: AppText.title3.copyWith(
                fontWeight: FontWeight.w700,
                color: today ? c.onAccent : c.label,
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
