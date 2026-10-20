import 'package:intl/intl.dart';

import '../../data/backend.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';

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
    PastorIdentity(:final services?) => l10n.identityPastorOf(services.map(service).join(l10n.listSeparator)),
    ServiceLead(service: final id) => l10n.identityLeadOf(service(id)),
    MinistryLead(:final ministry) => l10n.identityLeadOf(ministries?.byId(ministry)?.name ?? ministry),
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
    PastorIdentity(:final services?) => l10n.canServiceLead(services.map(service).join(l10n.listSeparator)),
    ServiceLead(service: final id) => l10n.canServiceLead(service(id)),
    MinistryLead(:final ministry) => l10n.canMinistryLead(ministries?.byId(ministry)?.name ?? ministry),
    SmallGroupLead(:final smallGroup) => l10n.canSmallGroupLead(smallGroupName(smallGroups, smallGroup)),
  };
}

/// [member]'s 身分 in a line, e.g. 「牧者 · 全教會、敬拜團 負責人」; empty for a
/// plain 同工.
String identitiesLine(
  L10n l10n,
  Member member, {
  required ServiceSettings? services,
  required MinistrySettings? ministries,
  List<SmallGroupDetails> smallGroups = const [],
}) => member.identities
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
