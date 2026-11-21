import 'models.dart';
import 'text.dart';

/// Everyone a roster can name (#94): the members, and, as members, the
/// 同工 without an account yet (moved from self-host, or added by name),
/// who are 同工 all the same.
///
/// Names are the same however written ([nameKey]): one without an account
/// under a member's name is that member, waiting to be merged, and not
/// listed twice; a new 同工 cannot take a name already here.
class Staff {
  factory Staff(
    List<Member> members, {
    List<PendingMember> pending = const [],
    List<SmallGroupDetails> smallGroups = const [],
  }) {
    final memberKeys = {for (final m in members) nameKey(m.name)};
    final waiting = <String, List<PendingMember>>{};
    final all = [...members];
    for (final p in pending) {
      final key = nameKey(p.name);
      if (memberKeys.contains(key)) {
        (waiting[key] ??= []).add(p);
      } else {
        all.add(p.asMember(smallGroups));
      }
    }
    return Staff._(all, {for (final p in pending) p.id}, {for (final m in all) nameKey(m.name)}, waiting);
  }

  Staff._(this.all, this.noAccount, this._keys, this._waiting);

  static final empty = Staff(const []);

  /// Members first, then those without an account.
  final List<Member> all;

  /// The IDs of those without an account: nobody to notify, or to sign in.
  final Set<String> noAccount;

  final Set<String> _keys;
  final Map<String, List<PendingMember>> _waiting;
  final _searchKeys = <String, String>{};

  /// Whether one of the 同工 goes by [name], however it is written.
  bool hasName(String name) {
    final key = nameKey(name);
    return key.isNotEmpty && _keys.contains(key);
  }

  /// Those whose name has [query] in it, however written, in [all]'s order.
  List<Member> search(String query) {
    final q = nameKey(query);
    if (q.isEmpty) return all;
    return [
      for (final m in all)
        if (_searchKeys.putIfAbsent(m.name, () => nameKey(m.name)).contains(q)) m,
    ];
  }

  /// The one without an account under [member]'s name, for an admin to
  /// merge: none when two are.
  PendingMember? waitingToMerge(Member member) => switch (_waiting[nameKey(member.name)]) {
    [final only] => only,
    _ => null,
  };
}
