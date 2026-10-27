import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';

/// The city a church's time zone is shown by.
String timeZoneCity(L10n l10n, ChurchTimeZone timeZone) => switch (timeZone) {
  ChurchTimeZone.auckland => l10n.cityAuckland,
  ChurchTimeZone.sydney => l10n.citySydney,
  ChurchTimeZone.melbourne => l10n.cityMelbourne,
  ChurchTimeZone.tokyo => l10n.cityTokyo,
  ChurchTimeZone.seoul => l10n.citySeoul,
  ChurchTimeZone.taipei => l10n.cityTaipei,
  ChurchTimeZone.hongKong => l10n.cityHongKong,
  ChurchTimeZone.singapore => l10n.citySingapore,
  ChurchTimeZone.kualaLumpur => l10n.cityKualaLumpur,
  ChurchTimeZone.london => l10n.cityLondon,
  ChurchTimeZone.newYork => l10n.cityNewYork,
  ChurchTimeZone.toronto => l10n.cityToronto,
  ChurchTimeZone.chicago => l10n.cityChicago,
  ChurchTimeZone.denver => l10n.cityDenver,
  ChurchTimeZone.losAngeles => l10n.cityLosAngeles,
  ChurchTimeZone.vancouver => l10n.cityVancouver,
};

/// `UTC+8`, `UTC−7` (a minus sign, not a hyphen), `UTC+5:30`; `UTC` itself.
String utcOffset(Duration offset) {
  if (offset == Duration.zero) return 'UTC';
  final minutes = offset.inMinutes.abs();
  final mm = minutes % 60 == 0 ? '' : ':${(minutes % 60).toString().padLeft(2, '0')}';
  return 'UTC${offset.isNegative ? '−' : '+'}${minutes ~/ 60}$mm';
}

/// `洛杉磯（UTC−7）`: [timeZone]'s city and how far it is from UTC at [now],
/// which summer time changes.
String timeZoneLabel(L10n l10n, ChurchTimeZone timeZone, DateTime now) =>
    l10n.timeZoneWithOffset(timeZoneCity(l10n, timeZone), utcOffset(timeZone.offsetAt(now)));

/// Instants as the church's clock reads them, in the language shown: every
/// time on screen is the church's, wherever the phone is.
class ChurchClock {
  ChurchClock(this._l10n, this.timeZone);

  /// The church [ref] reads, in [context]'s language.
  factory ChurchClock.of(BuildContext context, WidgetRef ref) =>
      ChurchClock(L10n.of(context), ref.watch(churchTimeZoneProvider));

  final L10n _l10n;
  final ChurchTimeZone timeZone;

  /// 10/18 14:05, Oct 18 14:05: when something was read or sent.
  String moment(DateTime instant) => shortMonthDay(_l10n).add_Hm().format(timeZone.clock(instant));

  /// 10月18日, Oct 18: the day of [instant].
  String day(DateTime instant) => DateFormat.MMMd().format(timeZone.clock(instant));

  /// 剛剛, 3 分鐘前, 5 小時前 at [now]; a day or more before, [moment]:
  /// when a notification came.
  String ago(DateTime instant, DateTime now) {
    final since = now.difference(instant);
    if (since.inMinutes < 1) return _l10n.notifJustNow;
    if (since.inHours < 1) return _l10n.notifMinutesAgo(since.inMinutes);
    if (since.inDays < 1) return _l10n.notifHoursAgo(since.inHours);
    return moment(instant);
  }

  /// 2026年10月18日, Oct 18, 2026: the day of [instant], with its year.
  String dayWithYear(DateTime instant) => DateFormat.yMMMd().format(timeZone.clock(instant));
}

/// How far the phone's clock is ahead of UTC at an instant. Tests put the
/// phone elsewhere.
final deviceOffsetProvider = Provider<Duration Function(DateTime)>(
  (_) =>
      (t) => t.toLocal().timeZoneOffset,
);

/// The time zone a church made on this phone starts in: the phone's, or
/// the nearest the app knows ([ChurchTimeZone.forDevice]). Its admin can change
/// it later.
final deviceTimeZoneProvider = Provider<Future<ChurchTimeZone> Function()>(
  (ref) => () async {
    final now = ref.read(clockProvider)();
    String? id;
    try {
      id = (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      // Not told: the phone's clock alone.
    }
    return ChurchTimeZone.forDevice(id, ref.read(deviceOffsetProvider)(now), now);
  },
);

/// "教會當地時間（台北）" under the times of the church's calendar, when the
/// phone's clock reads otherwise: they are the church's, not the phone's.
class ChurchClockNotice extends ConsumerWidget {
  const ChurchClockNotice({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.xs),
  });

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeZone = ref.watch(churchTimeZoneProvider);
    final now = ref.watch(clockProvider)();
    if (ref.watch(deviceOffsetProvider)(now) == timeZone.offsetAt(now)) return const SizedBox.shrink();
    final l10n = L10n.of(context);
    return Padding(
      padding: padding,
      child: Text(
        l10n.churchLocalTime(timeZoneCity(l10n, timeZone)),
        style: AppText.footnote.copyWith(color: AppColors.of(context).secondaryLabel),
      ),
    );
  }
}
