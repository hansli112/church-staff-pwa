import 'package:church_staff_pwa/core/types/service_type.dart';

import '../../auth/domain/entities/user.dart';
import 'entities/event_option.dart';
import 'entities/service_roster.dart';
import 'roster_import_parser.dart';
import 'staff_directory.dart';

/// 一次匯入的結果：要嘛不能匯，要嘛是要寫的服事表加上寫完之後的報告。
sealed class RosterImportPlan {
  const RosterImportPlan();
}

/// 整份匯入不能進行。[message] 直接給使用者看。
class RosterImportRejected extends RosterImportPlan {
  const RosterImportRejected(this.message);

  final String message;
}

/// 可以寫了。
///
/// [summary] 是**假設 [updates] 全部寫成功**的報告 —— 寫入失敗時呼叫端改報
/// 失敗，不顯示它。
class RosterImportReady extends RosterImportPlan {
  const RosterImportReady({required this.updates, required this.summary});

  final List<ServiceRoster> updates;
  final RosterImportSummary summary;
}

/// 把貼上（或照片辨識出來）的 JSON 對到 [type] 現有的服事表上。
///
/// 不碰 Firestore：輸入是現況，輸出是要寫的東西。畫面只剩「讀現況、呼叫、
/// 寫入、顯示」—— 以前這段編排寫在 widget 的 State 裡，樣板排序、報告漏人
/// 那幾個 bug 都出在這裡，卻沒有任何測試碰得到。
///
/// [templates] 為 null 代表樣板還沒載入。[rosters] 只要 [type] 這個崇拜的。
RosterImportPlan planRosterImport({
  required String input,
  required ServiceType type,
  required List<User> users,
  required List<ServiceRoster> rosters,
  required Map<ServiceType, List<String>>? templates,
  required List<EventOption> eventOptions,
}) {
  final parsed = parseRosterImportJson(
    input: input,
    staff: StaffDirectory.fromUsers(users, type),
    catalogByName: {for (final option in eventOptions) option.name: option},
  );
  if (parsed.error case final error?) return RosterImportRejected(error);

  // 服事項目的順序完全由樣板決定，樣板不可靠就不能匯 —— 缺席時所有角色
  // 並列，會退回 JSON 的順序寫進 Firestore，畫面上看不出哪裡不對。
  //
  // 只擋含 duties 的匯入：只帶 events 的 JSON 根本不排序，沒有理由一起擋。
  //
  // 「載入過」不夠：寫入空樣板之後也算載入過，但這個崇拜的鍵可能根本不存
  // 在。真正要問的是「這個崇拜的樣板拿得到嗎」。
  final templateRoles = templates?[type];
  if (parsed.dutiesProvidedDates.isNotEmpty) {
    if (templates == null) {
      return const RosterImportRejected('服事項目樣板尚未載入，順序會排錯。請重新整理後再匯入');
    }
    if (templateRoles == null) {
      // 服事項目設定是 admin only，非 admin 連那顆按鈕都看不到，所以這裡
      // 講「請管理員」而不是「請先到」—— 後者對他是一條走不通的路。
      return RosterImportRejected('${type.label}還沒有服事項目樣板，順序會排錯。請管理員到服事項目設定新增');
    }
  }

  final rosterByDate = {
    for (final roster in rosters) rosterDateKey(roster.date): roster,
  };
  final updates = <ServiceRoster>[];
  final missingDates = <String>[];

  for (final key in {
    ...parsed.dutiesProvidedDates,
    ...parsed.eventsProvidedDates,
  }) {
    final roster = rosterByDate[key];
    if (roster == null) {
      missingDates.add(key);
      continue;
    }

    // 只帶 duties 的那天不動活動，只帶 events 的那天不動服事 —— JSON 裡沒有
    // 那個鍵就是「這次不改」，不是「清空」。有帶 events 的那天則整批換成
    // JSON 的活動與顏色：匯入是在重寫那一天，不是往上疊。
    final hasDuties = parsed.dutiesProvidedDates.contains(key);
    final hasEvents = parsed.eventsProvidedDates.contains(key);
    updates.add(
      roster.copyWith(
        duties: hasDuties
            ? orderDutiesByTemplate(
                parsed.dutiesByDate[key] ?? const [],
                templateRoles ?? const [],
              )
            : roster.duties,
        specialEvents: hasEvents
            ? (parsed.eventsByDate[key] ?? const <String>[])
            : roster.specialEvents,
        customEventColors: hasEvents
            ? (parsed.colorsByDate[key] ?? const <String, int>{})
            : roster.customEventColors,
      ),
    );
  }

  return RosterImportReady(
    updates: updates,
    summary: RosterImportSummary(
      updated: updates.length,
      missingDates: missingDates,
      notInRosterNames: parsed.notInRosterNames,
      guestSpeakerNames: parsed.guestSpeakerNames,
      // 刻意從 roleMismatchNames 反向長出來，而不是直接沿用 details：報告只
      // 畫得出這裡的人，兩份清單若對不齊，對不齊的那個人會從報告上整個消失。
      roleMismatchDetails: {
        for (final name in parsed.roleMismatchNames)
          name: (parsed.roleMismatchDetails[name]?.toList() ?? [])..sort(),
      },
      otherNames: parsed.otherNames,
      nearMatchSuggestions: parsed.nearMatchSuggestions,
      notInEventCatalog: parsed.notInEventCatalog,
    ),
  );
}

/// 服事表在匯入 JSON 裡的日期寫法：`YYYY-MM-DD`。
String rosterDateKey(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// 匯入之後的結果報告。
///
/// 沒對到的名字**已經照樣寫進服事表了**，列在這裡是讓你知道，不是要你回去
/// 補打名字，也不是叫你去改設定 —— 臨時支援別的崇拜是常態，那些人一年可能
/// 就來這麼一次，把他們設成固定班底反而會弄髒名單。
///
/// 所以文案一律只陳述事實，不寫祈使句。「新增服事至同工」那顆按鈕是備著的，不是
/// 建議的動作：真的多了一位固定班底時按一下省得跑一趟帳號管理，其餘時候
/// 放著就好。
class RosterImportSummary {
  const RosterImportSummary({
    required this.updated,
    required this.missingDates,
    required this.notInRosterNames,
    required this.roleMismatchDetails,
    required this.otherNames,
    required this.nearMatchSuggestions,
    required this.notInEventCatalog,
    this.guestSpeakerNames = const [],
  });

  final int updated;
  final List<String> missingDates;
  final List<String> notInRosterNames;

  /// 人名 → 他被排到、但設定裡沒有的服事。
  final Map<String, List<String>> roleMismatchDetails;

  final List<String> otherNames;

  /// 表上原字 → 名單裡跟它只差一個字的那幾位。**只是提示，沒有套用。**
  ///
  /// 這裡的名字同時在 [notInRosterNames] 裡（沒有 uid），所以不必另外算進
  /// [hasIssues] —— 它跟著「名單裡沒有這個人」那一段一起顯示。
  final Map<String, List<String>> nearMatchSuggestions;

  final List<String> notInEventCatalog;

  /// 外來講員：只排在信息、名單裡沒有也沒有很像的。**不算問題**，所以不進
  /// [hasIssues] 也不進 [hasUnmatchedNames] —— 列出來只是讓人知道這幾個名字
  /// 沒有連到帳號，而那對講員來說是正常的。
  final List<String> guestSpeakerNames;

  bool get hasIssues =>
      hasUnmatchedNames ||
      missingDates.isNotEmpty ||
      notInEventCatalog.isNotEmpty;

  /// 有沒有「人」沒對到。日期與活動不算 —— 那兩類跟「這些人已經排進去了」
  /// 那句安撫無關，不該一起把那句話帶出來。
  bool get hasUnmatchedNames =>
      notInRosterNames.isNotEmpty ||
      roleMismatchDetails.isNotEmpty ||
      otherNames.isNotEmpty;

  /// 能不能講「下面的名字都已經排進表裡了」。
  ///
  /// 未匹配的名單是整份 JSON 的統計，但日期找不到的那幾筆根本沒寫進去 ——
  /// 那些人名照樣會出現在清單上。只要有任何一天沒匯入，這句話就可能是假的；
  /// 一筆都沒更新時更是徹底的謊話。寧可不講，也不要讓管理者以為排好了。
  bool get canPromiseAllImported =>
      hasUnmatchedNames && updated > 0 && missingDates.isEmpty;
}
