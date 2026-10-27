import 'models.dart';

/// A group of the church with its name.
typedef NamedGroup = ({ChurchGroup group, String name});

/// The church's groups (#82–#85), each with its name: its services, 事工
/// and 小組, a 小組 resolved with the service it is in. What lists, names
/// or looks up a group asks this, so a 小組 never reaches a rule without
/// its service.
class ChurchGroups {
  ChurchGroups({
    required ServiceSettings services,
    required MinistrySettings ministries,
    required List<SmallGroupDetails> smallGroups,
  }) : _services = services,
       _ministries = ministries,
       _smallGroups = smallGroups;

  final ServiceSettings _services;
  final MinistrySettings _ministries;
  final List<SmallGroupDetails> _smallGroups;

  /// Every group to pick from, in order: the services in use, the 事工,
  /// the 小組.
  List<NamedGroup> get all => [
    for (final s in _services.enabled) (group: ServiceGroup(s.id), name: s.name),
    for (final m in _ministries.ministries) (group: MinistryGroup(m.id), name: m.name),
    for (final g in _smallGroups) (group: g.group, name: g.name),
  ];

  /// The group [key] ([ChurchGroup.key]) names, with its name, a service
  /// no longer in use too; null for the church's ('') or one gone.
  NamedGroup? byKey(String key) => switch (ChurchGroup.parse(key)) {
    ServiceGroup(:final id) => switch (_services.byId(id)) {
      final s? => (group: ServiceGroup(id), name: s.name),
      null => null,
    },
    MinistryGroup(:final id) => switch (_ministries.byId(id)) {
      final m? => (group: MinistryGroup(id), name: m.name),
      null => null,
    },
    SmallGroup(:final id) => switch (_smallGroups.byId(id)) {
      final g? => (group: g.group, name: g.name),
      null => null,
    },
    null => null,
  };

  /// The groups [me] leads, as 負責人, 牧者 or 小組長: services, then 事工,
  /// then 小組.
  List<NamedGroup> ledBy(Member me) => [
    for (final id in me.leadTypes)
      if (_services.byId(id) case final s?) (group: ServiceGroup(id), name: s.name),
    for (final id in me.leadMinistries)
      if (_ministries.byId(id) case final m?) (group: MinistryGroup(id), name: m.name),
    for (final g in _smallGroups)
      if (me.leadSmallGroups.contains(g.id)) (group: g.group, name: g.name),
  ];
}
