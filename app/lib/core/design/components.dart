/// The component library. Screens build from these instead of raw Material
/// widgets so the rules in docs/design-principles.md hold everywhere.
library;

import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoDialogAction;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import 'tokens.dart';

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
            padding: const EdgeInsetsDirectional.only(start: Space.m),
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
                child: Text(
                  header!,
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
              child: Text(
                footer!,
                style: AppText.footnote.copyWith(color: c.secondaryLabel),
              ),
            ),
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

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final platform = Theme.of(context).platform;
    final showChevron = chevron ?? (onTap != null && trailing == null && selected == null && !destructive);
    final row = InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: Space.minTap(platform)),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.m,
            vertical: 11,
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                IconTheme.merge(
                  data: IconThemeData(
                    color: destructive ? c.destructive : c.accent,
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
                    Text(
                      title,
                      style: AppText.body.copyWith(
                        color: destructive ? c.destructive : c.label,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: AppText.subheadline.copyWith(
                            color: c.secondaryLabel,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (value != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: Space.s),
                  child: Text(
                    value!,
                    style: AppText.body.copyWith(color: c.secondaryLabel),
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
                    Icons.check,
                    color: c.accent,
                    size: 22,
                    semanticLabel: L10n.of(context).selected,
                  ),
                ),
              if (showChevron)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: Space.xs),
                  child: Icon(
                    Icons.chevron_right,
                    color: c.tertiaryLabel,
                    size: 22,
                  ),
                ),
            ],
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
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: ListRow(
        title: title,
        subtitle: subtitle,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        trailing: Switch.adaptive(value: value, onChanged: onChanged),
      ),
    );
  }
}

/// One sentence and at most one button, inviting the next step.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
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
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: c.secondaryLabel),
            ),
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

/// A short message near the bottom; with [onUndo], an 「復原」 action.
///
/// Used instead of a confirmation dialog for anything that can be undone.
void showToast(
  BuildContext context,
  String message, {
  VoidCallback? onUndo,
  Duration duration = const Duration(seconds: 5),
}) {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = L10n.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: duration,
      persist: false,
      action: onUndo == null
          ? null
          : SnackBarAction(
              label: l10n.undo,
              onPressed: () {
                Haptics.light();
                onUndo();
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
      content: Text(message),
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
        content: message == null ? null : Text(message),
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
        content: message == null ? null : Text(message),
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
/// close.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool expand = false,
}) {
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
        prefixIcon: Icon(Icons.search, color: c.secondaryLabel),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: l10n.clear,
                icon: Icon(Icons.cancel, color: c.tertiaryLabel, size: 20),
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

/// Section title above content on a plain page, e.g. a date heading.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.m, Space.s),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                text,
                style: AppText.footnote.copyWith(
                  color: c.secondaryLabel,
                  fontWeight: FontWeight.w600,
                ),
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
