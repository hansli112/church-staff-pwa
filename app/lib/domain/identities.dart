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
      _ => null,
    };
  }

  Map<String, Object?> toJson();
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

/// A 事工's 負責人: arranges the duties it links, in any service and on
/// any event, and adds its 同工.
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

/// One duty of one service that a 事工 leads, e.g. 主日崇拜's 司琴.
@immutable
class MinistryDuty {
  const MinistryDuty(this.service, this.duty);

  final String service;
  final String duty;

  @override
  bool operator ==(Object other) => other is MinistryDuty && other.service == service && other.duty == duty;

  @override
  int get hashCode => Object.hash(service, duty);
}

/// A 事工 (#82), e.g. 敬拜團: its 負責人 arrange the [duties] it links;
/// one that links none (關懷事工) only has its 同工 and, later, events.
@immutable
class Ministry {
  const Ministry({required this.id, required this.name, this.duties = const []});

  /// Stable; never reused (settings/ministries `ids`).
  final String id;
  final String name;
  final List<MinistryDuty> duties;

  /// The duties it leads on a day of [serviceType], or, for an event's
  /// roster (in no service, [serviceType] null), every duty by name.
  Set<String> dutiesIn(String? serviceType) => {
    for (final d in duties)
      if (serviceType == null || d.service == serviceType) d.duty,
  };

  Ministry copyWith({String? name, List<MinistryDuty>? duties}) =>
      Ministry(id: id, name: name ?? this.name, duties: duties ?? this.duties);

  @override
  bool operator ==(Object other) =>
      other is Ministry && other.id == id && other.name == name && listEquals(other.duties, duties);

  @override
  int get hashCode => Object.hash(id, name, Object.hashAll(duties));
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
  /// `service:<id>`, `ministry:<id>` or `small:<id>`.
  String get key => switch (this) {
    ServiceGroup() => 'service:$id',
    MinistryGroup() => 'ministry:$id',
    SmallGroup() => 'small:$id',
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
      _ => null,
    };
  }
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

/// A 小組 (#85), by its ID; its name and service are [SmallGroupDetails].
final class SmallGroup extends ChurchGroup {
  const SmallGroup(super.id);

  @override
  bool operator ==(Object other) => other is SmallGroup && other.id == id;

  @override
  int get hashCode => Object.hash('small', id);
}

/// A 小組 (churches/{cid}/smallGroups/{id}): in one [service], and, for
/// 回報人數, when it meets: on [weekday] (1 = Monday … 7 = Sunday) every
/// [every] weeks (1 or 2) from [startsOn], a day it met.
@immutable
class SmallGroupDetails {
  const SmallGroupDetails({
    required this.id,
    required this.name,
    required this.service,
    this.weekday,
    this.every = 1,
    this.startsOn,
  });

  /// Empty for one not made yet; the backend gives it one.
  final String id;
  final String name;
  final String service;
  final int? weekday;
  final int every;
  final Day? startsOn;

  SmallGroup get group => SmallGroup(id);

  /// When it meets, for [attendanceDue].
  Meets get meets => Meets(weekday: weekday, every: every, startsOn: startsOn);

  SmallGroupDetails copyWith({
    String? name,
    int? Function()? weekday,
    int? every,
    Day? Function()? startsOn,
  }) => SmallGroupDetails(
    id: id,
    name: name ?? this.name,
    service: service,
    weekday: weekday == null ? this.weekday : weekday(),
    every: every ?? this.every,
    startsOn: startsOn == null ? this.startsOn : startsOn(),
  );

  @override
  bool operator ==(Object other) =>
      other is SmallGroupDetails &&
      other.id == id &&
      other.name == name &&
      other.service == service &&
      other.weekday == weekday &&
      other.every == every &&
      other.startsOn == startsOn;

  @override
  int get hashCode => Object.hash(id, name, service, weekday, every, startsOn);
}
