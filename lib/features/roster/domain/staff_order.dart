import 'package:church_staff_pwa/core/types/service_type.dart';

import 'entities/service_roster.dart';
import 'staff_directory.dart';

/// 一個服事項目由前到後的同工。選人視窗拖完送出的就是這個。
class StaffRanking {
  const StaffRanking(this.role, this.names);

  final String role;
  final List<String> names;
}

/// 一個崇拜裡，每個服事項目的同工排序：主要的人排前面。
///
/// 順序是「人」的屬性，不是「某一天」的屬性。以前每一天各存一份順序，交換
/// 是就地換掉那個位置上的人 —— 主要同工換到別天就排到第二個，換進來的人
/// 反而跑到第一個。現在每一天的名字一律照這份排，交換、匯入、勾選都不必
/// 再管位置。
///
/// 服事表的圖片本身就照這個順序排，所以匯入時直接從圖片學（見
/// [StaffOrder.learnFrom]）；在選人視窗拖曳則是調整這一份。
class StaffOrder {
  StaffOrder([Map<String, List<String>> rankingsByRole = const {}])
    : _byRole = Map.unmodifiable({
        for (final entry in rankingsByRole.entries)
          if (entry.key.trim().isNotEmpty)
            entry.key.trim(): List<String>.unmodifiable(
              _cleanNames(entry.value),
            ),
      });

  final Map<String, List<String>> _byRole;

  /// 有排過順序的服事項目 → 由前到後的名字。
  Map<String, List<String>> get rankingsByRole => _byRole;

  bool get isEmpty => _byRole.isEmpty;

  /// [role] 的排序。沒排過就是空的。
  List<String> rankingOf(String role) => _byRole[role.trim()] ?? const [];

  /// 把 [people] 照 [role] 的排序排好。
  ///
  /// 排序裡沒有的人（例如外請講員）接在後面，彼此維持原本的先後。只有一個
  /// 人、或全部都不在排序裡時原樣回傳同一個 List，呼叫端可以用 `identical`
  /// 知道什麼都沒變。
  List<String> sort(String role, List<String> people) {
    if (people.length < 2) return people;
    final ranking = rankingOf(role);
    if (ranking.isEmpty) return people;
    final rank = {for (var i = 0; i < ranking.length; i++) ranking[i]: i};
    final indexed = [
      for (var i = 0; i < people.length; i++) (name: people[i], at: i),
    ];
    // 不在排序裡的人排在所有排過的人之後，自己人之間照原本位置 —— 用原
    // 位置當第二鍵，Dart 的 sort 不保證穩定。
    indexed.sort((a, b) {
      final ra = rank[a.name.trim()] ?? ranking.length;
      final rb = rank[b.name.trim()] ?? ranking.length;
      if (ra != rb) return ra.compareTo(rb);
      return a.at.compareTo(b.at);
    });
    var changed = false;
    for (var i = 0; i < indexed.length; i++) {
      if (indexed[i].at != i) {
        changed = true;
        break;
      }
    }
    if (!changed) return people;
    return [for (final entry in indexed) entry.name];
  }

  /// 照這份排序排好 [roster] 裡每一項服事的人。沒有任何改變時回傳同一個
  /// 物件。
  ServiceRoster applyTo(ServiceRoster roster) {
    if (isEmpty) return roster;
    var changed = false;
    final duties = [
      for (final duty in roster.duties)
        () {
          final sorted = sort(duty.role, duty.people);
          if (identical(sorted, duty.people)) return duty;
          changed = true;
          return duty.copyWith(people: sorted);
        }(),
    ];
    return changed ? roster.copyWith(duties: duties) : roster;
  }

  /// 換掉 [role] 的排序。[ranking] 是空的就等於拿掉這一項。
  StaffOrder withRanking(String role, List<String> ranking) {
    final key = role.trim();
    final next = Map<String, List<String>>.of(_byRole);
    final cleaned = _cleanNames(ranking);
    if (cleaned.isEmpty) {
      next.remove(key);
    } else {
      next[key] = cleaned;
    }
    return StaffOrder(next);
  }

  /// 把 [newer] 排過的服事項目併進來：[newer] 提到的人照它的先後，沒提到
  /// 的人留在原位。
  ///
  /// 「留在原位」而不是「排到最後」：主要同工這一季請假、不在這次的圖片上，
  /// 不代表他不再是主要同工 —— 擠到最後的話，他回來那天就排在新人後面。
  ///
  /// 做法是把 [newer] 也有的那幾個人原本佔的位置，照 [newer] 的順序重新填
  /// 一次；只有 [newer] 有的人插在 [newer] 裡他前一位的後面（他是第一位時插
  /// 在後面第一個認得的人前面）。
  StaffOrder mergedWith(StaffOrder newer) {
    final next = Map<String, List<String>>.of(_byRole);
    for (final entry in newer._byRole.entries) {
      next[entry.key] = _merge(next[entry.key] ?? const [], entry.value);
    }
    return StaffOrder(next);
  }

  static List<String> _merge(List<String> base, List<String> newer) {
    final baseSet = base.toSet();
    final newerSet = newer.toSet();
    final known = newer.where(baseSet.contains).iterator;
    final result = [
      for (final name in base)
        if (newerSet.contains(name)) (known..moveNext()).current else name,
    ];
    for (var i = 0; i < newer.length; i++) {
      final name = newer[i];
      if (baseSet.contains(name)) continue;
      if (i > 0) {
        result.insert(result.indexOf(newer[i - 1]) + 1, name);
        continue;
      }
      final following = newer.skip(1).where(baseSet.contains).firstOrNull;
      if (following == null) {
        result.add(name);
      } else {
        result.insert(result.indexOf(following), name);
      }
    }
    return result;
  }

  /// 只留 [keep] 認得的人。匯入時用來把外請講員這類名單外的名字拿掉 ——
  /// 他們在圖片上排第幾只是那一次的事，寫進固定排序的話，之後新加入的同工
  /// 都會排在他們後面。
  StaffOrder where(bool Function(String name) keep) => StaffOrder({
    for (final entry in _byRole.entries)
      entry.key: entry.value.where(keep).toList(),
  });

  /// 變成 [next] 要改哪些服事項目：有變的給新的排序，拿掉的給 null。
  ///
  /// 寫回 Firestore 只寫這幾項，不整份覆寫 —— 這台裝置手上的排序可能是舊的
  /// （別人剛改過別項），也可能根本沒讀到，整份寫回會把別人的改動蓋掉。
  Map<String, List<String>?> changesTo(StaffOrder next) {
    final changes = <String, List<String>?>{};
    for (final entry in next._byRole.entries) {
      if (!_sameNames(_byRole[entry.key], entry.value)) {
        changes[entry.key] = entry.value;
      }
    }
    for (final role in _byRole.keys) {
      if (!next._byRole.containsKey(role)) changes[role] = null;
    }
    return changes;
  }

  /// 套上 [changesTo] 算出來的改動。
  StaffOrder withChanges(Map<String, List<String>?> changes) {
    final next = Map<String, List<String>>.of(_byRole);
    for (final entry in changes.entries) {
      final ranking = entry.value;
      if (ranking == null) {
        next.remove(entry.key);
      } else {
        next[entry.key] = ranking;
      }
    }
    return StaffOrder(next);
  }

  /// 服事項目改名時，排序跟著搬過去。
  StaffOrder withRolesRenamed(Map<String, String> renamed) {
    if (renamed.isEmpty) return this;
    final next = <String, List<String>>{};
    for (final entry in _byRole.entries) {
      next[renamed[entry.key] ?? entry.key] = entry.value;
    }
    return StaffOrder(next);
  }

  /// 從現有的服事表學出排序：每個人在那一項服事裡平均排第幾。
  ///
  /// 平均而不是「最後一次」：圖片偶爾會把兩個人的先後寫反，一次例外不該
  /// 蓋掉其他幾週的共識。平均一樣時照先出現的排（[rosters] 由早到晚給）。
  ///
  /// 只有一個人的那幾天不算：沒有別人可以比，放進來只會把大家的平均都往
  /// 0 拉，讓「總是一個人上」的服事項目也排出一份沒有意義的順序。
  static StaffOrder learnFrom(Iterable<ServiceRoster> rosters) {
    final totals = <String, Map<String, ({int sum, int count, int first})>>{};
    var seen = 0;
    for (final roster in rosters) {
      for (final duty in roster.duties) {
        final people = _cleanNames(duty.people);
        if (people.length < 2) continue;
        final byName = totals.putIfAbsent(duty.role.trim(), () => {});
        for (var i = 0; i < people.length; i++) {
          final prev = byName[people[i]];
          byName[people[i]] = (
            sum: (prev?.sum ?? 0) + i,
            count: (prev?.count ?? 0) + 1,
            first: prev?.first ?? seen,
          );
          seen++;
        }
      }
    }
    return StaffOrder({
      for (final entry in totals.entries)
        entry.key:
            (entry.value.entries.toList()..sort((a, b) {
                  final avgA = a.value.sum / a.value.count;
                  final avgB = b.value.sum / b.value.count;
                  if (avgA != avgB) return avgA.compareTo(avgB);
                  return a.value.first.compareTo(b.value.first);
                }))
                .map((e) => e.key)
                .toList(),
    });
  }

  factory StaffOrder.fromJson(Map<String, dynamic> json) {
    final roles = json['roles'];
    if (roles is! Map) return StaffOrder();
    return StaffOrder({
      for (final entry in roles.entries)
        if (entry.key is String && entry.value is List)
          entry.key as String: [
            for (final name in entry.value as List)
              if (name is String) name,
          ],
    });
  }

  Map<String, dynamic> toJson() => {'roles': _byRole};

  @override
  bool operator ==(Object other) {
    if (other is! StaffOrder) return false;
    if (other._byRole.length != _byRole.length) return false;
    for (final entry in _byRole.entries) {
      if (!_sameNames(other._byRole[entry.key], entry.value)) return false;
    }
    return true;
  }

  static bool _sameNames(List<String>? a, List<String> b) {
    if (a == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(
    _byRole.entries.map((e) => Object.hash(e.key, Object.hashAll(e.value))),
  );

  /// trim、去掉空白與「待定」、去重，保留先後。
  static List<String> _cleanNames(Iterable<String> names) {
    final result = <String>[];
    for (final raw in names) {
      final name = raw.trim();
      if (name.isEmpty || name == placeholderPerson) continue;
      if (result.contains(name)) continue;
      result.add(name);
    }
    return result;
  }
}

/// 每個崇拜實際採用的同工排序。
///
/// 存下來的（有人拖過、或匯入時從圖片學的）優先；沒存過的服事項目退回從
/// 現有服事表學出來的順序，所以這個功能上線前的資料一樣排得好。
class StaffOrderBook {
  StaffOrderBook({
    Map<ServiceType, StaffOrder> stored = const {},
    Map<ServiceType, StaffOrder> learned = const {},
  }) : _stored = stored,
       _learned = learned;

  final Map<ServiceType, StaffOrder> _stored;
  final Map<ServiceType, StaffOrder> _learned;
  final Map<ServiceType, StaffOrder> _effective = {};

  /// [type] 存在 Firestore 上的那份（就這台裝置所知）。
  StaffOrder storedFor(ServiceType type) => _stored[type] ?? StaffOrder();

  /// [type] 實際拿來排的那份。
  StaffOrder effectiveFor(ServiceType type) => _effective[type] ??=
      (_learned[type] ?? StaffOrder()).mergedWith(storedFor(type));

  /// 照 [roster] 那個崇拜的排序排好。
  ServiceRoster sort(ServiceRoster roster) =>
      effectiveFor(roster.type).applyTo(roster);

  /// 從 [rosters] 重新學一次。只給「從外面讀進來」的資料用：本機寫入前已經
  /// 照排序排好，拿來重學只會得到一樣的東西。
  StaffOrderBook relearnedFrom(Iterable<ServiceRoster> rosters) =>
      StaffOrderBook(
        stored: _stored,
        learned: {
          for (final type in ServiceType.values)
            type: StaffOrder.learnFrom(rosters.where((r) => r.type == type)),
        },
      );

  StaffOrderBook withStored(Map<ServiceType, StaffOrder> stored) =>
      StaffOrderBook(stored: stored, learned: _learned);

  StaffOrderBook withStoredFor(ServiceType type, StaffOrder order) =>
      withStored({..._stored, type: order});
}
