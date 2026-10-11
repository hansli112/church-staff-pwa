import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';

/// Why the church link's content source gave nothing usable today.
String linkErrorText(L10n l10n, LinkFetchError error, int? status) => switch (error) {
  LinkFetchError.timeout => l10n.linkErrTimeout,
  LinkFetchError.tooLarge => l10n.linkErrTooLarge,
  LinkFetchError.badFormat => l10n.linkErrBadFormat,
  LinkFetchError.notToday => l10n.linkErrNotToday,
  LinkFetchError.notHttps => l10n.linkErrNotHttps,
  LinkFetchError.http => l10n.linkErrHttp('${status ?? ''}'),
  LinkFetchError.network => l10n.linkErrNetwork,
  LinkFetchError.unknown => l10n.linkErrUnknown,
};
