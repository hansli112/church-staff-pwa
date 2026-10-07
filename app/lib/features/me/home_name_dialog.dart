import 'package:flutter/material.dart';

import '../../domain/limits.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';

/// Asks for the home-screen name. Returns the trimmed name, '' to go back
/// to the church name, or null when cancelled.
Future<String?> askHomeName(BuildContext context, {required String churchName, String? current}) =>
    showAdaptiveDialog<String>(
      context: context,
      builder: (context) => _HomeNameDialog(churchName: churchName, initial: current ?? ''),
    );

class _HomeNameDialog extends StatefulWidget {
  const _HomeNameDialog({required this.churchName, required this.initial});

  final String churchName;
  final String initial;

  @override
  State<_HomeNameDialog> createState() => _HomeNameDialogState();
}

class _HomeNameDialogState extends State<_HomeNameDialog> {
  late final _controller = TextEditingController(text: widget.initial)..addListener(() => setState(() {}));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final long = _controller.text.trim().characters.length > Church.homeNameSafeLength;
    return AlertDialog(
      title: Text(l10n.homeName),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: TextLimits.homeName,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: widget.churchName,
          helperText: long ? l10n.homeNameMayBeCut : l10n.homeNameFooter,
          helperMaxLines: 3,
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        TextButton(onPressed: _save, child: Text(l10n.save)),
      ],
    );
  }
}
