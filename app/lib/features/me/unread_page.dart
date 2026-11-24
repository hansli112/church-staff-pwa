import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../core/design/components.dart';
import '../../l10n/app_localizations.dart';

/// The first of [reads] that failed with nothing read before, if any;
/// watched, so the page shows 重試 once one fails.
ProviderBase<AsyncValue<Object?>>? failedRead(WidgetRef ref, List<ProviderBase<AsyncValue<Object?>>> reads) {
  for (final p in reads) {
    if (ref.watch(p.select((AsyncValue<Object?> v) => v.hasError && !v.hasValue))) return p;
  }
  return null;
}

/// A page with nothing to show yet: blank while [reads] load, or 重試 when
/// one failed, reading it again. Blank too when they are read and what the
/// page is about is not there (removed).
Scaffold unreadPage(
  BuildContext context,
  WidgetRef ref,
  List<ProviderBase<AsyncValue<Object?>>> reads, {
  Widget? title,
}) {
  final failed = failedRead(ref, reads);
  return Scaffold(
    appBar: AppBar(title: title),
    body: failed == null
        ? null
        : ErrorRetry(message: L10n.of(context).loadFailed, onRetry: () => ref.invalidate(failed)),
  );
}
