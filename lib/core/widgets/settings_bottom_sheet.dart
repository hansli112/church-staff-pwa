import 'package:flutter/material.dart';

class SettingsBottomSheet extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback? onSubmit;
  final String submitLabel;
  final String cancelLabel;
  final Widget? submitChild;

  /// 為 true 時，按鈕顯示 spinner + `${submitLabel}中…`（例：'匯入中…'）。
  /// 呼叫端應確保 submitLabel 是可組合的動詞。
  final bool isSubmitting;

  const SettingsBottomSheet({
    super.key,
    required this.title,
    required this.child,
    required this.onSubmit,
    this.submitLabel = '儲存',
    this.cancelLabel = '取消',
    this.submitChild,
    this.isSubmitting = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              child: Text(title, style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(child: child),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
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
                  child:
                      submitChild ??
                      (isSubmitting
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: theme.colorScheme.onPrimary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('$submitLabel中…'),
                              ],
                            )
                          : Text(submitLabel)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
