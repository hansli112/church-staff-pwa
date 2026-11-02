import 'package:flutter/foundation.dart';

import 'attendance.dart';
import 'day.dart';
import 'models.dart' show ServiceSettings;

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
/// one that links none (多媒體) is only what calendar events belong to.
/// Most belong to one service, each with its own 敬拜團 ([service]); some
/// serve several, or none, the church's (跨聚會的事工).
@immutable
class Ministry {
  const Ministry({required this.id, required this.name, this.duties = const [], this.addedIn});

  /// Stable; never reused (settings/ministries `ids`).
  final String id;
  final String name;
  final List<MinistryDuty> duties;

  /// The service it was added on, before it links any duty there.
  final String? addedIn;

  /// The service it belongs to: the one every duty it links is in, or,
  /// linking none, the one it was added on; null for one in several
  /// services, or in none.
  String? get service => switch ({for (final d in duties) d.service}) {
    final s when s.isEmpty => addedIn,
    final s when s.length == 1 => s.single,
    _ => null,
  };

  /// The duties it leads on a day of [serviceType], or, for an event's
  /// roster (in no service, [serviceType] null), every duty by name.
  Set<String> dutiesIn(String? serviceType) => {
    for (final d in duties)
      if (serviceType == null || d.service == serviceType) d.duty,
  };

  Ministry copyWith({String? name, List<MinistryDuty>? duties}) =>
      Ministry(id: id, name: name ?? this.name, duties: duties ?? this.duties, addedIn: addedIn);

  @override
  bool operator ==(Object other) =>
      other is Ministry &&
      other.id == id &&
      other.name == name &&
      listEquals(other.duties, duties) &&
      other.addedIn == addedIn;

  @override
  int get hashCode => Object.hash(id, name, Object.hashAll(duties), addedIn);
}

/// What someone arranges of a roster (#82): all of it, or only some of
/// its duties, those the 事工 they lead link ([none]: nothing at all).
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

  /// The name of 事工 [id] wherever those of every service show together:
  /// with its service's, 「青年崇拜 · 敬拜團」, when another has the same
  /// name (each service its own 敬拜團); [id] for one gone.
  String nameOf(String id, ServiceSettings? services) {
    final m = byId(id);
    if (m == null) return id;
    final service = m.service;
    if (service == null || !ministries.any((o) => o.id != id && o.name == m.name)) return m.name;
    return '${services?.byId(service)?.name ?? service} · ${m.name}';
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

  SmallGroup get group => SmallGroup(id, service: service);

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

/// The church's 小組 by ID.
extension SmallGroupsById on List<SmallGroupDetails> {
  SmallGroupDetails? byId(String id) => where((g) => g.id == id).firstOrNull;
}
