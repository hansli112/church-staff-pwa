import 'package:church_staff_pwa/core/types/service_type.dart';

import '../../auth/domain/entities/user.dart';

/// 服事表上代表「還沒排到人」的佔位字串。
///
/// 它是佔位不是人，所以不能跟真名並存 —— 選人的 dialog、交換、匯入都照這個
/// 規則處理。放在 domain 而不是某個 provider 上，是因為讀寫服事表的每一層都
/// 要認得它。
const String placeholderPerson = '待定';

/// 某一個崇拜的同工名單：回答「表上這個名字是誰」與「他能不能排這個服事」。
///
/// 以前這兩個問題在匯入、選人、交換各算一次，各自決定要不要 trim、同名時
/// 取哪個 uid。收在這裡之後規則只有一份。
class StaffDirectory {
  /// 直接給名單。正式流程用 [StaffDirectory.fromUsers]；這個給測試跟
  /// 已經有名單、沒有 [User] 物件的呼叫端。
  StaffDirectory({
    required List<String> names,
    Map<String, String> idByName = const {},
    Map<String, Set<String>> namesByRole = const {},
  }) : _names = List.unmodifiable(names),
       _nameSet = names.toSet(),
       _idByName = Map.unmodifiable(idByName),
       _namesByRole = Map.unmodifiable(namesByRole);

  /// [type] 這個崇拜的名單。名字都 trim 過，空白的名字不算。
  ///
  /// 同名同姓的人**不帶 uid**：兩位都叫王大明時，挑哪一位都是猜，猜錯的話
  /// 提醒發給另一個人，而且沒有任何跡象。不帶 uid 時首頁的「我的服事」會
  /// 退回姓名比對，兩位都看得到 —— 多一個人看到，好過對的人看不到。
  factory StaffDirectory.fromUsers(List<User> users, ServiceType type) {
    final names = <String>[];
    final idByName = <String, String>{};
    final duplicates = <String>{};
    final namesByRole = <String, Set<String>>{};
    for (final user in users) {
      final name = user.name.trim();
      if (name.isEmpty) continue;
      if (names.contains(name)) duplicates.add(name);
      names.add(name);
      final uid = user.id.trim();
      if (uid.isNotEmpty) idByName.putIfAbsent(name, () => uid);
      for (final zone in user.zones) {
        if (zone.serviceType != type) continue;
        for (final ministry in zone.ministries) {
          final role = ministry.trim();
          if (role.isEmpty) continue;
          namesByRole.putIfAbsent(role, () => <String>{}).add(name);
        }
      }
    }
    return StaffDirectory(
      names: names,
      idByName: {
        for (final entry in idByName.entries)
          if (!duplicates.contains(entry.key)) entry.key: entry.value,
      },
      namesByRole: namesByRole,
    );
  }

  final List<String> _names;
  final Set<String> _nameSet;

  bool _isDuplicate(String name) =>
      _names.indexOf(name) != _names.lastIndexOf(name);
  final Map<String, String> _idByName;
  final Map<String, Set<String>> _namesByRole;

  /// 名單上所有人（所有崇拜），順序照原本的名單。同名同姓的會出現兩次。
  List<String> get names => _names;

  /// 名字 → uid。同名同姓的名字不在裡面（見 [StaffDirectory.fromUsers]）。
  Map<String, String> get idByName => _idByName;

  bool contains(String name) => _nameSet.contains(name.trim());

  String? idOf(String name) => _idByName[name.trim()];

  /// 這些名字裡查得到 uid 的那幾個。
  Map<String, String> idsOf(Iterable<String> names) => {
    for (final name in names) name: ?idOf(name),
  };

  /// 這個人在這個崇拜的服事設定裡有沒有 [role]。
  bool canServe(String name, String role) =>
      _namesByRole[role.trim()]?.contains(name.trim()) ?? false;

  /// 服事設定裡有 [role] 的人，依名字排序。
  List<String> namesForRole(String role) =>
      (_namesByRole[role.trim()]?.toList() ?? <String>[])..sort();

  /// 表上寫的 [raw] 是名單上的誰，排在 [role] 合不合他的設定。
  ///
  /// 三層：全名、名單上唯一一位的字尾（表上常省略姓氏）、差一個字的提示。
  /// 前兩層會改寫成名單上的全名；第三層**不改**，只附上候選。
  NameMatchResult resolve(String raw, String role) {
    final name = raw.trim();
    if (name.isEmpty || name == placeholderPerson) {
      return const NameMatchResult.matched(placeholderPerson);
    }
    if (_nameSet.contains(name)) {
      // 名單上有兩位以上叫這個名字：是誰由人決定，跟字尾對到兩位一樣處理。
      if (_isDuplicate(name)) return NameMatchResult.other(name);
      return canServe(name, role)
          ? NameMatchResult.matched(name)
          : NameMatchResult.roleMismatch(name);
    }
    final matches = _names
        .where((full) => full.length > name.length && full.endsWith(name))
        .toList();
    if (matches.length == 1) {
      final full = matches.first;
      return canServe(full, role)
          ? NameMatchResult.matched(full)
          : NameMatchResult.roleMismatch(full);
    }
    if (matches.length > 1) {
      return NameMatchResult.other(name);
    }
    // 前兩層都是精確比對，錯一個字就是查無此人 —— 而中文名字的罕用字正是 OCR
    // 最容易認錯的地方。這一層不改結果，只把名單裡差一個字的那幾位附上去，讓
    // 管理者自己判斷是不是某位的別寫法。為什麼不自動接，見 [NameMatchResult]
    // 的 suggestions。
    return NameMatchResult.notInList(
      name,
      suggestions: _nearMatches(name, _names),
    );
  }
}

enum NameMatchStatus { matched, notInList, roleMismatch, other }

class NameMatchResult {
  final NameMatchStatus status;
  final String name;

  /// 名單裡跟這個名字只差一個字的那幾位 —— **只是提示，沒有套用**。
  ///
  /// 只會跟 [NameMatchStatus.notInList] 一起出現：名字照表上原文寫進服事表，
  /// uid 一個都不帶，這幾個候選只是列給人看的。
  ///
  /// 不自動接回去是量過之後的決定：名單內部互相拼錯一個字時，唯一對到「別的
  /// 真人」的情況是 0 次；會落進這一層的幾乎都是**還沒有帳號的人**（新同工、
  /// 外來講員），而他們的名字常常跟某個真人只差一個字（「陳志豪」對上名單裡
  /// 的「陳志明」）。自動接的話那個人的服事會被記到別人頭上、連上別人的 uid，
  /// 提醒發給錯的人，而原本那個名字從表上消失。提示看得到就夠了。
  final List<String> suggestions;

  const NameMatchResult(this.status, this.name, {this.suggestions = const []});
  const NameMatchResult.matched(this.name)
    : status = NameMatchStatus.matched,
      suggestions = const [];
  const NameMatchResult.notInList(this.name, {this.suggestions = const []})
    : status = NameMatchStatus.notInList;
  const NameMatchResult.roleMismatch(this.name)
    : status = NameMatchStatus.roleMismatch,
      suggestions = const [];
  const NameMatchResult.other(this.name)
    : status = NameMatchStatus.other,
      suggestions = const [];
}

/// 少於這麼多個字就不給形近字提示。
///
/// 一個字的輸入會對上半本名單，那種提示沒有意義。兩個字的照樣比 —— 結果只是
/// 提示不會套用，所以「小明」順便對上「劉美玉」的代價只是多一行字，而漏掉
/// 「雅亭」對上「黃雅婷」才是真的可惜。
const int _minNearMatchRunes = 2;

/// [a] 與 [b] 等長、而且逐位比對剛好只差一個字時回 true。
///
/// 位置對位置，不做插入／刪除 —— 形近字是替換，長度不變。改成編輯距離會
/// 讓「王大明」對上「王大明峰」這種真的不同的名字。
bool _differsByOneRune(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    if (a[i] == b[i]) continue;
    diff++;
    if (diff > 1) return false;
  }
  return diff == 1;
}

/// 名單裡跟 [name] 只差一個字的全名。
///
/// 規則刻意收得很緊，因為猜錯的代價是把服事排到另一個真人身上：
///
/// - 只准差一個字，而且輸入至少要有 [_minNearMatchRunes] 個字。
/// - 表上寫的常是去掉姓氏的簡稱，所以比的是名單那位的**同長度尾段**。
/// - 回傳全部候選，讓呼叫端在「不唯一」時退回「不確定是哪一位」，不挑。
///
/// 用 runes 而不是 String 的字元索引：罕用字有些落在 BMP 之外（例如 CJK
/// 擴充 B 區），那些字在 Dart 的 String 裡是兩個 code unit，逐 code unit
/// 比會把一個字算成兩個位置。而罕用字正是這一層要救的東西。
List<String> _nearMatches(String name, List<String> userNames) {
  final target = name.runes.toList();
  if (target.length < _minNearMatchRunes) return const [];
  final matches = <String>[];
  for (final full in userNames) {
    final runes = full.runes.toList();
    if (runes.length < target.length) continue;
    final tail = runes.sublist(runes.length - target.length);
    if (_differsByOneRune(target, tail)) matches.add(full);
  }
  return matches;
}
