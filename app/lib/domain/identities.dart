import 'package:flutter/foundation.dart';

import 'attendance.dart';
import 'day.dart';

/// A 身分 (#82): what someone is in a church, which is also what they may
/// do there. A member may hold several; most hold none and are a 同工.
/// Stored as `identities` on the member doc, beside the projections the
/// security rules read (Member.withIdentities).
@immutable
sealed class Identity {
  const Identity();

  /// One stored 身分; null for a kind this app does not know.
  static Identity? fromJson(Object? json) {
    if (json is! Map) return null;
    return switch (json['kind']) {
      'admin' => const AdminIdentity(),
      'office' => const OfficeIdentity(),
      'pastor' => switch (json['services']) {
        final List<Object?> services => PastorIdentity([
          for (final s in services)
            if (s is String) s,
        ]),
        _ => const PastorIdentity(null),
      },
      'lead' => switch ((json['service'], json['ministry'], json['smallGroup'])) {
        (final String service, _, _) => ServiceLead(service),
        (_, final String ministry, _) => MinistryLead(ministry),
        (_, _, final String smallGroup) => SmallGroupLead(smallGroup),
        _ => null,
      },
      'dutyLead' => switch ((json['service'], json['duty'])) {
        (final String service, final String duty) when service.isNotEmpty && duty.isNotEmpty => DutyLead(service, duty),
        _ => null,
      },
      _ => null,
    };
  }

  Map<String, Object?> toJson();

  /// Whether it makes its holder an admin: 管理員, or a whole church's 牧者.
  bool get makesAdmin => switch (this) {
    AdminIdentity() || PastorIdentity(services: null) => true,
    _ => false,
  };
}

/// 管理員: everything.
final class AdminIdentity extends Identity {
  const AdminIdentity();

  @override
  Map<String, Object?> toJson() => {'kind': 'admin'};

  @override
  bool operator ==(Object other) => other is AdminIdentity;

  @override
  int get hashCode => 'admin'.hashCode;
}

/// 行政: arranges every roster and edits the calendar; manages no one.
final class OfficeIdentity extends Identity {
  const OfficeIdentity();

  @override
  Map<String, Object?> toJson() => {'kind': 'office'};

  @override
  bool operator ==(Object other) => other is OfficeIdentity;

  @override
  int get hashCode => 'office'.hashCode;
}

/// 牧者, of the whole church ([services] null: as an admin) or of some
/// services (as their 負責人). Shown as 牧者 wherever they serve.
final class PastorIdentity extends Identity {
  const PastorIdentity(this.services);

  final List<String>? services;

  bool get wholeChurch => services == null;

  @override
  Map<String, Object?> toJson() => {'kind': 'pastor', 'services': ?services};

  @override
  bool operator ==(Object other) =>
      other is PastorIdentity && (other.services == null) == (services == null) && listEquals(other.services, services);

  @override
  int get hashCode => Object.hash('pastor', services == null ? null : Object.hashAll(services!));
}

/// A service's 負責人: arranges its rosters, adds its 同工.
final class ServiceLead extends Identity {
  const ServiceLead(this.service);

  final String service;

  @override
  Map<String, Object?> toJson() => {'kind': 'lead', 'service': service};

  @override
  bool operator ==(Object other) => other is ServiceLead && other.service == service;

  @override
  int get hashCode => Object.hash('service', service);
}

/// A 事工's 負責人: makes the 事工's events on the calendar and arranges
/// their rosters (a 事工 links no duties, 2026-11-26).
final class MinistryLead extends Identity {
  const MinistryLead(this.ministry);

  final String ministry;

  @override
  Map<String, Object?> toJson() => {'kind': 'lead', 'ministry': ministry};

  @override
  bool operator ==(Object other) => other is MinistryLead && other.ministry == ministry;

  @override
  int get hashCode => Object.hash('ministry', ministry);
}

/// A 服事項目's 負責人, e.g. 主日崇拜's 攝影 (2026-11-26): arranges that
/// duty on the service's days, and who is on its list. Stored with its own
/// kind, which apps from before it do not read as a service's 負責人.
final class DutyLead extends Identity {
  const DutyLead(this.service, this.duty);

  final String service;
  final String duty;

  /// As the rules and the backend read it, in `leadDuties`:
  /// `<service>/<duty>` (a service's ID has no slash).
  String get key => '$service/$duty';

  /// [key] read back; null for anything else.
  static DutyLead? parse(String key) {
    final at = key.indexOf('/');
    return at > 0 && at < key.length - 1 ? DutyLead(key.substring(0, at), key.substring(at + 1)) : null;
  }

  @override
  Map<String, Object?> toJson() => {'kind': 'dutyLead', 'service': service, 'duty': duty};

  @override
  bool operator ==(Object other) => other is DutyLead && other.service == service && other.duty == duty;

  @override
  int get hashCode => Object.hash('duty', service, duty);
}

/// 小組長 (#85): fills in the 小組's 人數, makes its events, adds its 同工.
final class SmallGroupLead extends Identity {
  const SmallGroupLead(this.smallGroup);

  final String smallGroup;

  @override
  Map<String, Object?> toJson() => {'kind': 'lead', 'smallGroup': smallGroup};

  @override
  bool operator ==(Object other) => other is SmallGroupLead && other.smallGroup == smallGroup;

  @override
  int get hashCode => Object.hash('smallGroup', smallGroup);
}

/// A 事工 (#82), e.g. 多媒體: a team with its 負責人 and its own events on
/// the calendar, at no fixed time (what meets every week is a service).
/// It links no duties (2026-11-26): a duty's 負責人 is held on the duty
/// ([DutyLead]).
@immutable
class Ministry {
  const Ministry({required this.id, required this.name});

  /// Stable; never reused (settings/ministries `ids`).
  final String id;
  final String name;

  Ministry copyWith({String? name}) => Ministry(id: id, name: name ?? this.name);

  @override
  bool operator ==(Object other) => other is Ministry && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// What someone arranges of a roster (#82): all of it, or only some of
/// its duties, those they are the 負責人 of ([none]: nothing at all).
@immutable
class Arranges {
  const Arranges.all() : _duties = null;
  const Arranges.only(Set<String> duties) : _duties = duties;

  static const none = Arranges.only({});

  final Set<String>? _duties;

  /// All of it: every duty, the 特別活動 and the staff order.
  bool get all => _duties == null;

  /// Anything at all.
  bool get any => _duties == null || _duties.isNotEmpty;

  /// Whether [duty] is theirs to arrange.
  bool has(String duty) => _duties == null || _duties.contains(duty);

  @override
  bool operator ==(Object other) =>
      other is Arranges && (other._duties == null) == (_duties == null) && setEquals(other._duties, _duties);

  @override
  int get hashCode => _duties == null ? 0 : Object.hashAllUnordered(_duties);
}

/// settings/ministries: the church's 事工, and every ID it has ever used.
@immutable
class MinistrySettings {
  const MinistrySettings({this.ministries = const [], this.ids = const []});

  final List<Ministry> ministries;

  /// Only grows, so an ID once on a member keeps meaning one 事工.
  final List<String> ids;

  Ministry? byId(String id) {
    for (final m in ministries) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// The name of 事工 [id]; [id] for one gone.
  String nameOf(String id) => byId(id)?.name ?? id;

  MinistrySettings withMinistries(List<Ministry> next) => MinistrySettings(
    ministries: next,
    ids: [
      ...ids,
      for (final m in next)
        if (!ids.contains(m.id)) m.id,
    ],
  );

  @override
  bool operator ==(Object other) =>
      other is MinistrySettings && listEquals(other.ministries, ministries) && listEquals(other.ids, ids);

  @override
  int get hashCode => Object.hash(Object.hashAll(ministries), Object.hashAll(ids));
}

/// A group whose 同工 its 負責人 manage (#82): a service (its 牧區), a
/// 事工, or a 小組 (#85).
@immutable
sealed class ChurchGroup {
  const ChurchGroup(this.id);

  final String id;

  /// How an event, and its 人數, name it as its group (#84):
  /// `service:<id>`, `ministry:<id>` or `small:<id>`; a 其他聚會's 人數,
  /// `gathering:<id>`.
  String get key => switch (this) {
    ServiceGroup() => 'service:$id',
    MinistryGroup() => 'ministry:$id',
    SmallGroup() => 'small:$id',
    GatheringGroup() => 'gathering:$id',
  };

  /// [key] read back; null for the church's ('') or anything else.
  static ChurchGroup? parse(String key) {
    final i = key.indexOf(':');
    if (i <= 0 || i == key.length - 1) return null;
    final id = key.substring(i + 1);
    return switch (key.substring(0, i)) {
      'service' => ServiceGroup(id),
      'ministry' => MinistryGroup(id),
      'small' => SmallGroup(id),
      'gathering' => GatheringGroup(id),
      _ => null,
    };
  }
}

/// A 其他聚會 (Gathering): a group only for its 人數, with no 同工, 負責人
/// or events of its own.
final class GatheringGroup extends ChurchGroup {
  const GatheringGroup(super.id);

  @override
  bool operator ==(Object other) => other is GatheringGroup && other.id == id;

  @override
  int get hashCode => Object.hash('gathering', id);
}

final class ServiceGroup extends ChurchGroup {
  const ServiceGroup(super.id);

  @override
  bool operator ==(Object other) => other is ServiceGroup && other.id == id;

  @override
  int get hashCode => Object.hash('service', id);
}

final class MinistryGroup extends ChurchGroup {
  const MinistryGroup(super.id);

  @override
  bool operator ==(Object other) => other is MinistryGroup && other.id == id;

  @override
  int get hashCode => Object.hash('ministry', id);
}

/// A 小組 (#85), by its ID, with the [service] it is in when known (null:
/// read from a key, or one gone); [ChurchGroups] resolves it. One 小組
/// whatever is known of it: equal by ID. Its name and when it meets are
/// [SmallGroupDetails].
final class SmallGroup extends ChurchGroup {
  const SmallGroup(super.id, {this.service});

  final String? service;

  @override
  bool operator ==(Object other) => other is SmallGroup && other.id == id;

  @override
  int get hashCode => Object.hash('small', id);
}

/// A 小組 (churches/{cid}/smallGroups/{id}): in one [service], and, for
/// 回報人數, when it meets ([time]): on [weekday] (1 = Monday … 7 = Sunday)
/// every [every] weeks (1 or 2) from [startsOn], a day it met, or those
/// [monthWeeks] of each month.
@immutable
class SmallGroupDetails {
  const SmallGroupDetails({
    required this.id,
    required this.name,
    required this.service,
    this.weekday,
    this.every = 1,
    this.startsOn,
    this.monthWeeks = const [],
    this.order,
  });

  /// Empty for one not made yet; the backend gives it one.
  final String id;
  final String name;
  final String service;
  final int? weekday;
  final int every;
  final Day? startsOn;
  final List<int> monthWeeks;

  /// Where it is among its service's 小組, as dragged (orderSmallGroups);
  /// null for one never placed, after them (byOrder).
  final int? order;

  SmallGroup get group => SmallGroup(id, service: service);

  /// What [byOrder] sorts it by.
  Place get place => (order: order, name: name);

  /// Its 聚會時間.
  MeetingTime get time => MeetingTime(weekday: weekday, every: every, startsOn: startsOn, monthWeeks: monthWeeks);

  /// When it meets, for [attendanceDue].
  Meets get meets => time.meets();

  SmallGroupDetails copyWith({
    String? name,
    int? Function()? weekday,
    int? every,
    Day? Function()? startsOn,
    List<int>? monthWeeks,
    int? Function()? order,
  }) => SmallGroupDetails(
    id: id,
    name: name ?? this.name,
    service: service,
    weekday: weekday == null ? this.weekday : weekday(),
    every: every ?? this.every,
    startsOn: startsOn == null ? this.startsOn : startsOn(),
    monthWeeks: monthWeeks ?? this.monthWeeks,
    order: order == null ? this.order : order(),
  );

  /// With [time] as its 聚會時間.
  SmallGroupDetails withTime(MeetingTime time) => copyWith(
    weekday: () => time.weekday,
    every: time.every,
    startsOn: () => time.startsOn,
    monthWeeks: time.monthWeeks,
  );

  @override
  bool operator ==(Object other) =>
      other is SmallGroupDetails &&
      other.id == id &&
      other.name == name &&
      other.service == service &&
      other.weekday == weekday &&
      other.every == every &&
      other.startsOn == startsOn &&
      listEquals(other.monthWeeks, monthWeeks) &&
      other.order == order;

  @override
  int get hashCode => Object.hash(id, name, service, weekday, every, startsOn, Object.hashAll(monthWeeks), order);
}

/// The church's 小組 by ID.
extension SmallGroupsById on List<SmallGroupDetails> {
  SmallGroupDetails? byId(String id) => where((g) => g.id == id).firstOrNull;

  /// As the church lists them: by service, as [services] (their ids) has
  /// them, then each service's in the order dragged (byOrder).
  List<SmallGroupDetails> inChurchOrder(List<String> services) => _byService(services, (a, b) => 0);

  /// As 回報人數 lists them: by service, then each service's by the
  /// weekday they meet on, Sunday first as 人數總覽's week, those with no
  /// 聚會時間 last; on the same day, in the order dragged.
  List<SmallGroupDetails> inMeetingOrder(List<String> services) =>
      _byService(services, (a, b) => _inWeek(a.weekday).compareTo(_inWeek(b.weekday)));

  /// [weekday]'s place in a week from Sunday; none last.
  static int _inWeek(int? weekday) => weekday == null ? 7 : weekday % 7;

  List<SmallGroupDetails> _byService(
    List<String> services,
    int Function(SmallGroupDetails a, SmallGroupDetails b) within,
  ) {
    int at(String service) => switch (services.indexOf(service)) {
      -1 => services.length,
      final i => i,
    };
    return [...this]..sort(
      (a, b) => switch (at(a.service).compareTo(at(b.service))) {
        0 => switch (within(a, b)) {
          0 => byOrder(a.place, b.place),
          final c => c,
        },
        final c => c,
      },
    );
  }
}
