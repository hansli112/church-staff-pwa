import 'package:intl/intl.dart';

import '../../data/backend.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/support.dart';

/// Whether 身分 [i] is of something the church still has: not of a
/// deleted service, nor of a 小組 that went with it. Kept while [services]
/// or [smallGroups] are not known.
bool identityStands(Identity i, {required ServiceSettings? services, List<SmallGroupDetails>? smallGroups}) =>
    switch (i) {
      ServiceLead(service: final id) => services == null || services.byId(id) != null,
      PastorIdentity(services: final ids?) => services == null || ids.any((id) => services.byId(id) != null),
      SmallGroupLead(:final smallGroup) => smallGroups == null || smallGroups.byId(smallGroup) != null,
      _ => true,
    };

/// The names of [ids] among [services], not of one deleted.
String _serviceNames(L10n l10n, List<String> ids, ServiceSettings? services) => [
  for (final id in ids)
    if (services == null) id else ?services.byId(id)?.name,
].join(l10n.listSeparator);

/// How a 身分 (#82) is shown, e.g. 「敬拜團 負責人」, with the names of the
/// church's [services], [ministries] and [smallGroups].
String identityLabel(
  L10n l10n,
  Identity i, {
  required ServiceSettings? services,
  required MinistrySettings? ministries,
  List<SmallGroupDetails> smallGroups = const [],
}) {
  String service(String id) => services?.byId(id)?.name ?? id;
  return switch (i) {
    AdminIdentity() => l10n.roleAdmin,
    OfficeIdentity() => l10n.identityOffice,
    PastorIdentity(services: null) => l10n.identityPastorChurch,
    PastorIdentity(services: final ids?) => l10n.identityPastorOf(_serviceNames(l10n, ids, services)),
    ServiceLead(service: final id) => l10n.identityLeadOf(service(id)),
    MinistryLead(:final ministry) => l10n.identityLeadOf(ministries?.nameOf(ministry, services) ?? ministry),
    SmallGroupLead(:final smallGroup) => l10n.identitySmallGroupLeadOf(smallGroupName(smallGroups, smallGroup)),
  };
}

/// The name of 小組 [id] in [smallGroups], or [id] for one no longer there.
String smallGroupName(List<SmallGroupDetails> smallGroups, String id) => smallGroups.byId(id)?.name ?? id;

/// What a 身分 lets them do, in one sentence.
String identityCan(
  L10n l10n,
  Identity i, {
  required ServiceSettings? services,
  required MinistrySettings? ministries,
  List<SmallGroupDetails> smallGroups = const [],
}) {
  String service(String id) => services?.byId(id)?.name ?? id;
  return switch (i) {
    AdminIdentity() || PastorIdentity(services: null) => l10n.canAdmin,
    OfficeIdentity() => l10n.canOffice,
    PastorIdentity(services: final ids?) => l10n.canServiceLead(_serviceNames(l10n, ids, services)),
    ServiceLead(service: final id) => l10n.canServiceLead(service(id)),
    MinistryLead(:final ministry) => l10n.canMinistryLead(ministries?.nameOf(ministry, services) ?? ministry),
    SmallGroupLead(:final smallGroup) => l10n.canSmallGroupLead(smallGroupName(smallGroups, smallGroup)),
  };
}

/// [member]'s 身分 in a line, e.g. 「全教會 牧者、敬拜團 負責人」; empty for a
/// plain 同工.
String identitiesLine(
  L10n l10n,
  Member member, {
  required ServiceSettings? services,
  required MinistrySettings? ministries,
  List<SmallGroupDetails> smallGroups = const [],
}) => member.identities
    .where((i) => identityStands(i, services: services))
    .map((i) => identityLabel(l10n, i, services: services, ministries: ministries, smallGroups: smallGroups))
    .join(l10n.listSeparator);

/// 1 = Monday … 7 = Sunday.
String weekdayLabel(L10n l10n, int weekday) => switch (weekday) {
  1 => l10n.weekday1,
  2 => l10n.weekday2,
  3 => l10n.weekday3,
  4 => l10n.weekday4,
  5 => l10n.weekday5,
  6 => l10n.weekday6,
  _ => l10n.weekday7,
};

/// The days a service meets, in order: 週日; 週三、週日; three or more in
/// a row as one, 週一到週五.
String weekdaysLabel(L10n l10n, List<int> weekdays) {
  final parts = <String>[];
  for (var i = 0; i < weekdays.length;) {
    var j = i;
    while (j + 1 < weekdays.length && weekdays[j + 1] == weekdays[j] + 1) {
      j++;
    }
    if (j - i >= 2) {
      parts.add(l10n.weekdayRange(weekdayLabel(l10n, weekdays[i]), weekdayLabel(l10n, weekdays[j])));
    } else {
      parts.addAll([for (var k = i; k <= j; k++) weekdayLabel(l10n, weekdays[k])]);
    }
    i = j + 1;
  }
  return parts.join(l10n.listSeparator);
}

String currencyLabel(L10n l10n, Currency c) => switch (c) {
  Currency.twd => l10n.currencyTwd,
  Currency.usd => l10n.currencyUsd,
};

/// NT\$1,400 or US\$99.
String money(L10n l10n, num amount, [Currency currency = Currency.twd]) {
  final n = NumberFormat('#,##0.##').format(amount);
  return switch (currency) {
    Currency.twd => l10n.moneyTwd(n),
    Currency.usd => l10n.moneyUsd(n),
  };
}

/// The name of app icon [id] (null: the usual one); a church's is its name.
String appIconName(L10n l10n, String? id) => switch (id) {
  'Green' => l10n.appIconGreen,
  'Purple' => l10n.appIconPurple,
  'Night' => l10n.appIconNight,
  _ => churchIcons.values.where((c) => c.iconId == id).firstOrNull?.name ?? l10n.appIconDefault,
};
