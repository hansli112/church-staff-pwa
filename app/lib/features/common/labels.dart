import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';

String roleLabel(L10n l10n, Role role) => switch (role) {
  Role.admin => l10n.roleAdmin,
  Role.leader => l10n.roleLeader,
  Role.staff => l10n.roleStaff,
  Role.member => l10n.roleMember,
};

String groupLabel(L10n l10n, Group group) => switch (group) {
  Group.rosterEditors => l10n.groupRosterEditors,
  Group.calendarEditors => l10n.groupCalendarEditors,
};

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
