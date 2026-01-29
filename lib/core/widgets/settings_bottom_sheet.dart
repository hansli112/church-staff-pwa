import 'package:flutter/material.dart';

class SettingsBottomSheet extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback? onSubmit;
  final String submitLabel;
  final String cancelLabel;
  final Widget? submitChild;

  const SettingsBottomSheet({
    super.key,
    required this.title,
    required this.child,
    required this.onSubmit,
    this.submitLabel = '儲存',
    this.cancelLabel = '取消',
    this.submitChild,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(child: child),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(cancelLabel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onSubmit,
                  child: submitChild ?? Text(submitLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
