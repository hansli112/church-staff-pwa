import 'dart:developer';

import 'package:flutter/material.dart';
import '../../domain/entities/event_option.dart';
import '../../domain/entities/service_roster.dart';
import 'package:church_staff_pwa/core/types/service_type.dart';
import '../../domain/repositories/roster_repository.dart';
import '../../../../core/utils/error_messages.dart';
import '../../../../core/widgets/text_warmup.dart';

class RosterProvider with ChangeNotifier {
  final RosterRepository _repository;

  List<ServiceRoster> _allRosters = []; // 儲存所有原始資料
  Map<ServiceType, List<String>> _templates = {};

  /// 樣板是否真的從伺服器讀回來過。
  ///
  /// 不能用 `_templates.isEmpty` 或 `templates[type] == null` 代替：讀取失敗、
  /// 尚未讀取、與「這個類別本來就沒設定角色」在資料上長得一樣，但對匯入來說
  /// 意義完全不同 —— 前兩者會讓匯入排出錯誤的順序。
  bool _templatesLoaded = false;
  Map<ServiceType, List<EventOption>> _eventOptionsByType = {};
  bool _isLoading = false;
  bool _isEditMode = false;
  String? _error;

  // 追蹤上一次 session userId，用來判斷帳號是否真的換了。
  String? _lastSessionUserId;

  // Fetch generation counter：每次 session 變動或主動觸發 fetch 時遞增。
  // fetch 完成後比對 token，若不一致代表已過期，直接 drop 結果。
  int _fetchToken = 0;

  // ── 衍生資料快取 ────────────────────────────────────────────────────────
  // UI 每次 rebuild 都會問「這個牧區有哪些 roster」「這個事件是什麼顏色」。
  // 現算的話等於每個 frame 都掃一次全部資料，所以算一次存起來，
  // 只在 _allRosters / _eventOptionsByType 真的變動時丟掉。
  // 一律透過 _replaceRosters / _replaceRosterAt / _replaceEventOptions
  // 改資料，才不會有人漏掉 invalidate。
  Map<ServiceType, List<ServiceRoster>>? _rostersByType;
  Map<String, int>? _eventColorIndex;
  List<String>? _displayStrings;

  // 事件選項的版本號。UI 想知道「顏色定義有沒有換過」時可以 select 這個值 ——
  // eventOptionsByType 每次呼叫都會產生新的 Map，拿來做相等比較永遠會是 true。
  int _eventOptionsRevision = 0;

  RosterProvider(this._repository);

  /// 事件選項的版本號，每次選項被替換就 +1。
  /// widget 用 `context.select((p) => p.eventOptionsRevision)` 訂閱顏色變動。
  int get eventOptionsRevision => _eventOptionsRevision;

  /// 換掉整份 roster 清單。
  ///
  /// [rosters] 的 identity 本身就是「資料換過了」的訊號 —— 消費端（例如首頁
  /// 的本季服事 memo）用 `identical()` 判斷要不要重算，所以任何內容變動都
  /// **必須**換成新的 List instance，不能就地改寫。
  void _replaceRosters(List<ServiceRoster> rosters) {
    _allRosters = rosters;
    _rostersByType = null;
    _displayStrings = null;
  }

  /// 換掉單筆 roster。刻意複製一份新 List 而不是 `_allRosters[index] = ...` ——
  /// 就地改寫會讓 `rosters` 的 identity 不變，靠 identity 判斷是否失效的
  /// 消費端就會繼續用舊的計算結果。
  void _replaceRosterAt(int index, ServiceRoster roster) {
    final updated = List<ServiceRoster>.of(_allRosters);
    updated[index] = roster;
    _replaceRosters(updated);
  }

  void _replaceEventOptions(Map<ServiceType, List<EventOption>> options) {
    _eventOptionsByType = options;
    _eventColorIndex = null;
    _eventOptionsRevision++;
  }

  bool get isLoading => _isLoading;
  bool get isEditMode => _isEditMode;
  String? get error => _error;
  Map<ServiceType, List<String>> get templates => _templates;
  bool get templatesLoaded => _templatesLoaded;
  Map<ServiceType, List<EventOption>> get eventOptionsByType => Map.fromEntries(
    _eventOptionsByType.entries.map(
      (entry) => MapEntry(entry.key, List<EventOption>.from(entry.value)),
    ),
  );
  List<EventOption> eventOptionsFor(ServiceType type) =>
      List.unmodifiable(_eventOptionsByType[type] ?? const <EventOption>[]);

  /// 事件名稱 → 顏色。每張卡片的每個事件標籤在每次 rebuild 都會問一次，
  /// 所以用一份攤平的索引，不要每次都線性掃過所有 ServiceType 的清單。
  /// 同名事件以本 type 的定義優先，其次才是其他 type（維持原本語意）。
  int eventColorFor(ServiceType type, String name) {
    final own = _eventOptionsByType[type];
    if (own != null) {
      for (final option in own) {
        if (option.name == name) return option.color;
      }
    }
    return _colorIndex[name] ?? _fallbackEventColor;
  }

  static const int _fallbackEventColor = 0xFF7F8C8D;

  Map<String, int> get _colorIndex {
    final cached = _eventColorIndex;
    if (cached != null) return cached;

    final index = <String, int>{};
    for (final list in _eventOptionsByType.values) {
      for (final option in list) {
        index.putIfAbsent(option.name, () => option.color);
      }
    }
    _eventColorIndex = index;
    return index;
  }

  void toggleEditMode() {
    _isEditMode = !_isEditMode;
    notifyListeners();
  }

  /// 由 ChangeNotifierProxyProvider 在 SessionProvider.currentUser 變動時呼叫。
  /// 當 userId 真的改變（含登出 → null 或切換帳號），清掉全部 cache 並重抓資料。
  void onSessionChanged(String? userId) {
    if (userId == _lastSessionUserId) return;
    _lastSessionUserId = userId;

    _fetchToken++; // 讓進行中的 fetch 過期
    _replaceRosters([]);
    _templates = {};
    _templatesLoaded = false;
    _replaceEventOptions({});
    _error = null;
    _isEditMode = false;

    if (userId != null) {
      // 有新使用者，重抓資料。
      fetchInitialData();
    } else {
      // 登出，僅清除並通知 UI。
      notifyListeners();
    }
  }

  /// 取得特定類別的服事表。分組結果會快取 — UI 每次 rebuild 都會對三個
  /// ServiceType 各問一次，現算等於每個 frame 掃三遍全部 roster 並配置三個
  /// 新 List（也讓 ListView 每次都拿到不同的 list instance）。
  List<ServiceRoster> getRostersByType(ServiceType type) {
    final grouped = _rostersByType ??= _groupByType(_allRosters);
    return grouped[type] ?? const <ServiceRoster>[];
  }

  static Map<ServiceType, List<ServiceRoster>> _groupByType(
    List<ServiceRoster> all,
  ) {
    final grouped = <ServiceType, List<ServiceRoster>>{
      for (final type in ServiceType.values) type: <ServiceRoster>[],
    };
    for (final roster in all) {
      grouped[roster.type]?.add(roster);
    }
    return grouped;
  }

  // 為了相容性，如果有人直接 call rosters (雖然目前沒人用)，回傳全部
  List<ServiceRoster> get rosters => _allRosters;

  /// 服事表會顯示出來的所有不重複字串，給 [TextWarmup] 預熱用。
  ///
  /// 是「字串」不是「字元」：引擎的排版快取以整個字串為 key，只預熱字元只
  /// 會把字型抓下來，每個名字第一次排版的成本還是會落在捲動途中。
  List<String> get displayStrings {
    final cached = _displayStrings;
    if (cached != null) return cached;

    final sources = <String>[];
    for (final roster in _allRosters) {
      sources.add(roster.serviceName);
      sources.addAll(roster.specialEvents);
      for (final duty in roster.duties) {
        sources.add(duty.role);
        sources.addAll(duty.people);
      }
    }
    final strings = TextWarmup.uniqueStringsOf(sources);
    _displayStrings = strings;
    return strings;
  }

  Future<void> fetchInitialData() async {
    final token = ++_fetchToken;

    // Phase 1: cache-first — 從 IndexedDB 讀取（~50-150ms），有資料就先渲染。
    // isLoading 維持 true，但 UI 改成「isLoading && rosters.isEmpty」才顯示
    // spinner，所以有 stale data 時畫面不再卡白。
    try {
      final cached = await _repository.getUpcomingRostersFromCache();
      if (token != _fetchToken) return; // stale token，丟棄
      if (cached.isNotEmpty) {
        _replaceRosters(cached);
        notifyListeners(); // 先渲染 stale data
      }
    } catch (e, st) {
      log('讀取 roster cache 失敗（不影響後續 server fetch）', error: e, stackTrace: st);
      // cache 失敗不影響繼續走 server，silent
    }

    // Phase 2: server fetch — 拿到最新資料後覆蓋。
    _isLoading = true;
    _error = null;
    notifyListeners();

    // 三個請求同時發，但只有 roster 是必要的：服事表沒有 templates /
    // event options 一樣能顯示（那兩份只影響編輯用的選單與標籤顏色）。
    // 全部塞進同一個 Future.wait 的話，任何一份 settings 讀取失敗都會把
    // 已經成功抓到的 roster 一起丟掉，畫面變成「載入失敗」。
    final rostersFuture = _repository.getUpcomingRosters();
    final templatesFuture = _optional(
      _repository.getServiceTemplates(),
      '載入服事項目樣板失敗（不影響服事表顯示）',
    );
    final eventOptionsFuture = _optional(
      _repository.getEventOptions(),
      '載入事件選項失敗（不影響服事表顯示）',
    );

    try {
      final rosters = await rostersFuture;
      if (token != _fetchToken) return; // stale fetch，丟棄結果
      _replaceRosters(rosters);
    } catch (e, st) {
      if (token != _fetchToken) return; // stale fetch，丟棄錯誤
      log('載入服事表資料失敗', error: e, stackTrace: st);
      // 若 Phase 1 已拿到 cache 資料，就不設 _error（讓 UI 顯示 stale data 而非錯誤）
      if (_allRosters.isEmpty) {
        _error = '載入失敗:${mapErrorToUserMessage(e)}';
      } else {
        log('Server fetch 失敗，UI 繼續顯示 cache 資料', error: e, stackTrace: st);
      }
    } finally {
      // settings 失敗時保留上一次的值，不覆蓋成空的。
      final templates = await templatesFuture;
      final eventOptions = await eventOptionsFuture;
      if (token == _fetchToken) {
        if (templates != null) {
          _templates = templates;
          _templatesLoaded = true;
        }
        if (eventOptions != null) _replaceEventOptions(eventOptions);
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// 把「有了更好、沒有也能動」的請求包成永遠不會 reject 的 future：
  /// 失敗時 log 後回傳 null，讓呼叫端保留既有的值。
  static Future<T?> _optional<T>(Future<T> future, String failureMessage) {
    return future.then<T?>((value) => value).catchError((
      Object e,
      StackTrace st,
    ) {
      log(failureMessage, error: e, stackTrace: st);
      return null;
    });
  }

  Future<void> fetchRosters() async {
    final token = ++_fetchToken;

    // Phase 1: cache-first — 先顯示 stale data 避免白屏。
    try {
      final cached = await _repository.getUpcomingRostersFromCache();
      if (token != _fetchToken) return;
      if (cached.isNotEmpty) {
        _replaceRosters(cached);
        notifyListeners();
      }
    } catch (e, st) {
      log('讀取 roster cache 失敗（不影響後續 server fetch）', error: e, stackTrace: st);
    }

    // Phase 2: server fetch。
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final rosters = await _repository.getUpcomingRosters();
      if (token != _fetchToken) return; // stale fetch，丟棄結果
      _replaceRosters(rosters);
    } catch (e, st) {
      if (token != _fetchToken) return; // stale fetch，丟棄錯誤
      log('載入服事表失敗', error: e, stackTrace: st);
      if (_allRosters.isEmpty) {
        _error = '載入失敗:${mapErrorToUserMessage(e)}';
      } else {
        log('Server fetch 失敗，UI 繼續顯示 cache 資料', error: e, stackTrace: st);
      }
    } finally {
      if (token == _fetchToken) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// 只有具編輯權的人（admin / 負責人）才可呼叫。確保本季 + 下季、[allowedTypes]
  /// 範圍內的預定 roster 都已存在於 Firestore。
  ///
  /// [allowedTypes] 要傳呼叫者「改得動」的聚會別（[User.allowedRosterTypes]），
  /// 不是畫面上顯示的全部：多一個他無權寫的聚會別，整個 batch 都會被 rules 拒。
  /// 背景執行，失敗僅 log，不影響 UI。完成後觸發 fetchInitialData 讓新建的 roster 出現。
  Future<void> ensureQuarterRostersForEditor(
    List<ServiceType> allowedTypes,
  ) async {
    try {
      await _repository.ensureQuarterRosters(allowedTypes);
    } catch (e, st) {
      log('ensureQuarterRosters 失敗', error: e, stackTrace: st);
      // 靜默失敗，不 disrupt UI。
    }
    // backfill 成功與否都要重抓 —— backfill 只是「補齊缺的 roster」，
    // 它失敗不代表現有資料讀不到。放在 try 裡的話，backfill 一拋例外就會
    // 連重抓一起跳過，進編輯模式時畫面停在舊資料且毫無提示。
    await fetchInitialData();
  }

  Future<void> updateRoster(ServiceRoster roster) async {
    try {
      await _repository.updateRoster(roster);
      // Update local state
      final index = _allRosters.indexWhere((r) => r.id == roster.id);
      if (index != -1) {
        _replaceRosterAt(index, roster);
        notifyListeners();
      }
    } catch (e, st) {
      log('更新 roster 失敗', error: e, stackTrace: st);
      _error = '更新失敗:${mapErrorToUserMessage(e)}';
      notifyListeners();
    }
  }

  /// 服事表上代表「還沒排到人」的佔位字串。
  ///
  /// 它是佔位不是人，所以不能跟真名並存 —— 選人的 dialog 也是這樣處理的
  /// （`_RosterPeopleDialog._toggleSelection`）。
  static const String placeholderPerson = '待定';

  /// 把 [duty] 裡的 [from] 換成 [to]，其他人與既有順序都不動。
  ///
  /// [toId] 是 [to] 在對方那筆 duty 上記的 uid（可能沒有，例如「外請講員」這種
  /// 名單外的自訂名字）。要一起搬過來，否則推播就找不到這個人了。
  ///
  /// 兩個邊界：
  ///   - 換進來的人本來就在這一天：不要留下兩個同名，直接把重複的那個吃掉。
  ///     UI 已經先濾掉這種選項，這裡是第二道防線。
  ///   - 換成「待定」而這一天還有別人：只把 [from] 拿掉，不補佔位符；全空了
  ///     才補一個回去。
  @visibleForTesting
  static RosterEntry replaceDutyPerson(
    RosterEntry duty,
    String from,
    String to, {
    String? toId,
  }) {
    List<String> replaced(List<String> names) {
      final result = <String>[];
      for (final name in names) {
        if (name == from) {
          if (to != placeholderPerson && !result.contains(to)) result.add(to);
          continue;
        }
        if (name == to || name == placeholderPerson) continue;
        result.add(name);
      }
      return result;
    }

    // 沒有人的 duty 在 UI 上顯示成一個「待定」（見 _SwapDutyDialog），所以這裡
    // 也要把空清單當成 ['待定']，否則以待定為交換對象時 from 找不到對應項目，
    // 換過來的人會直接消失。
    final currentPeople = duty.people.isEmpty
        ? const [placeholderPerson]
        : duty.people;

    final people = replaced(currentPeople);
    if (people.isEmpty) people.add(placeholderPerson);

    // peopleOrder 是「people 去掉待定」的排列。舊資料（peopleOrder 這個欄位還
    // 沒有的年代）是空的，這時就照 people 的順序補起來 —— 反正下次有人在
    // dialog 按儲存也會寫成同一份。
    final order = duty.peopleOrder.isEmpty
        ? people.where((name) => name != placeholderPerson).toList()
        : replaced(duty.peopleOrder);

    final personIdsByName = Map<String, String>.from(duty.personIdsByName)
      ..remove(from);
    final trimmedToId = toId?.trim();
    if (trimmedToId != null && trimmedToId.isNotEmpty && people.contains(to)) {
      personIdsByName[to] = trimmedToId;
    }
    // 名字都不在這一天了，uid 留著只會在下次交換時被誤搬。
    personIdsByName.removeWhere((name, _) => !people.contains(name));

    return duty.copyWith(
      people: people,
      peopleOrder: order,
      personIdsByName: personIdsByName,
    );
  }

  /// 把兩張服事表上同一個服事項目的兩個人對調。
  ///
  /// 走 repository 的 batch 而不是兩次 [updateRoster]：交換的兩筆缺一不可，
  /// 一邊成功一邊失敗會留下一個人被排兩天、另一個人的那天空著，而且畫面上
  /// 兩邊看起來都換好了。
  ///
  /// 失敗往上丟，不吞進 [_error]：呼叫端的 sheet 要就地顯示錯誤讓人留在原地
  /// 重試，而不是關掉之後在服事表某處看到一行紅字。
  Future<void> swapDutyPeople({
    required String sourceRosterId,
    required int sourceDutyIndex,
    required String sourcePerson,
    required String targetRosterId,
    required int targetDutyIndex,
    required String targetPerson,
  }) async {
    final sourceIndex = _allRosters.indexWhere((r) => r.id == sourceRosterId);
    final targetIndex = _allRosters.indexWhere((r) => r.id == targetRosterId);
    if (sourceIndex < 0 || targetIndex < 0) {
      throw StateError('找不到要交換的服事表，請重新整理後再試');
    }
    if (sourceIndex == targetIndex) {
      throw ArgumentError('同一天的服事不需要交換');
    }

    final source = _allRosters[sourceIndex];
    final target = _allRosters[targetIndex];
    if (sourceDutyIndex < 0 ||
        sourceDutyIndex >= source.duties.length ||
        targetDutyIndex < 0 ||
        targetDutyIndex >= target.duties.length) {
      throw StateError('服事項目已變動，請重新整理後再試');
    }

    final sourceDuty = source.duties[sourceDutyIndex];
    final targetDuty = target.duties[targetDutyIndex];

    final newSourceDuties = List<RosterEntry>.of(source.duties);
    newSourceDuties[sourceDutyIndex] = replaceDutyPerson(
      sourceDuty,
      sourcePerson,
      targetPerson,
      toId: targetDuty.personIdsByName[targetPerson],
    );
    final newTargetDuties = List<RosterEntry>.of(target.duties);
    newTargetDuties[targetDutyIndex] = replaceDutyPerson(
      targetDuty,
      targetPerson,
      sourcePerson,
      toId: sourceDuty.personIdsByName[sourcePerson],
    );

    final newSource = source.copyWith(duties: newSourceDuties);
    final newTarget = target.copyWith(duties: newTargetDuties);

    await _repository.updateRostersAtomically([newSource, newTarget]);

    final updated = List<ServiceRoster>.of(_allRosters);
    updated[sourceIndex] = newSource;
    updated[targetIndex] = newTarget;
    _replaceRosters(updated);
    notifyListeners();
  }

  /// Batch-update rosters in parallel. On partial failure we still sync the
  /// successful writes into local state (so the UI matches Firestore truth)
  /// and then throw a summary so the caller can surface the partial error
  /// and offer "retry only failed". Plain `Future.wait` would also have
  /// written the same rows to Firestore but left local state empty,
  /// drifting the UI from the server.
  Future<void> updateRosters(List<ServiceRoster> rosters) async {
    if (rosters.isEmpty) return;
    final results = await Future.wait(
      rosters.map((roster) async {
        try {
          await _repository.updateRoster(roster);
          return (
            roster: roster,
            error: null as Object?,
            stackTrace: null as StackTrace?,
          );
        } catch (e, st) {
          return (
            roster: roster,
            error: e as Object?,
            stackTrace: st as StackTrace?,
          );
        }
      }),
    );

    final successes = results.where((r) => r.error == null).toList();
    if (successes.isNotEmpty) {
      // 一次算出新清單再換上去，不要逐筆呼叫 _replaceRosterAt（那會為每筆
      // 成功的寫入各複製一份完整清單）。
      final successById = {for (final r in successes) r.roster.id: r.roster};
      _replaceRosters(
        _allRosters.map((roster) => successById[roster.id] ?? roster).toList(),
      );
    }
    notifyListeners();

    final failures = results.where((r) => r.error != null).toList();
    if (failures.isNotEmpty) {
      throw PartialUpdateException(
        successCount: successes.length,
        failureCount: failures.length,
        failedRosters: failures.map((r) => r.roster).toList(),
        cause: failures.first.error!,
        causeStackTrace: failures.first.stackTrace,
      );
    }
  }

  Future<void> updateTemplates(
    Map<ServiceType, List<String>> newTemplates, {
    Map<ServiceType, Map<String, String>> renamedRolesByType = const {},
  }) async {
    try {
      await _repository.updateServiceTemplates(newTemplates);
      _templates = Map.from(newTemplates);
      _templatesLoaded = true;

      if (renamedRolesByType.isNotEmpty) {
        final updatedRosters = <ServiceRoster>[];
        for (final roster in _allRosters) {
          final renameMap = renamedRolesByType[roster.type];
          if (renameMap == null || renameMap.isEmpty) {
            continue;
          }

          var hasChanges = false;
          final updatedDuties = roster.duties.map((duty) {
            final renamedRole = renameMap[duty.role];
            if (renamedRole == null || renamedRole == duty.role) {
              return duty;
            }
            hasChanges = true;
            return duty.copyWith(role: renamedRole);
          }).toList();

          if (!hasChanges) {
            continue;
          }

          final updated = roster.copyWith(duties: updatedDuties);
          updatedRosters.add(updated);
        }

        if (updatedRosters.isNotEmpty) {
          await Future.wait(
            updatedRosters.map((roster) => _repository.updateRoster(roster)),
          );

          final updatedById = {
            for (final roster in updatedRosters) roster.id: roster,
          };
          _replaceRosters(
            _allRosters
                .map((roster) => updatedById[roster.id] ?? roster)
                .toList(),
          );
        }
      }

      notifyListeners();
    } catch (e, st) {
      log('更新服事表樣板失敗', error: e, stackTrace: st);
      _error = '更新失敗:${mapErrorToUserMessage(e)}';
      notifyListeners();
    }
  }

  Future<void> updateEventOptions(
    Map<ServiceType, List<EventOption>> options, {
    Map<ServiceType, Map<String, String>> renamedEventsByType = const {},
  }) async {
    try {
      await _repository.updateEventOptions(options);
      _replaceEventOptions(
        Map.fromEntries(
          options.entries.map(
            (entry) => MapEntry(entry.key, List<EventOption>.from(entry.value)),
          ),
        ),
      );

      if (renamedEventsByType.isNotEmpty) {
        final updatedRosters = <ServiceRoster>[];
        for (final roster in _allRosters) {
          final renameMap = renamedEventsByType[roster.type];
          if (renameMap == null || renameMap.isEmpty) {
            continue;
          }

          var hasChanges = false;
          final updatedEvents = roster.specialEvents.map((event) {
            final renamedEvent = renameMap[event];
            if (renamedEvent == null || renamedEvent == event) {
              return event;
            }
            hasChanges = true;
            return renamedEvent;
          }).toList();

          final newColors = Map<String, int>.from(roster.customEventColors);
          for (final entry in renameMap.entries) {
            final oldName = entry.key;
            final newName = entry.value;
            if (oldName == newName) continue;
            if (newColors.containsKey(oldName)) {
              newColors[newName] = newColors.remove(oldName)!;
              hasChanges = true;
            }
          }

          if (!hasChanges) {
            continue;
          }

          final updated = roster.copyWith(
            specialEvents: updatedEvents,
            customEventColors: newColors,
          );
          updatedRosters.add(updated);
        }

        if (updatedRosters.isNotEmpty) {
          await Future.wait(
            updatedRosters.map((roster) => _repository.updateRoster(roster)),
          );

          final updatedById = {
            for (final roster in updatedRosters) roster.id: roster,
          };
          _replaceRosters(
            _allRosters
                .map((roster) => updatedById[roster.id] ?? roster)
                .toList(),
          );
        }
      }

      notifyListeners();
    } catch (e, st) {
      log('更新事件選項失敗', error: e, stackTrace: st);
      _error = '更新失敗:${mapErrorToUserMessage(e)}';
      notifyListeners();
    }
  }
}

class PartialUpdateException implements Exception {
  final int successCount;
  final int failureCount;
  final List<ServiceRoster> failedRosters;
  final Object cause;
  final StackTrace? causeStackTrace;

  PartialUpdateException({
    required this.successCount,
    required this.failureCount,
    required this.failedRosters,
    required this.cause,
    this.causeStackTrace,
  });

  @override
  String toString() => '$successCount 筆寫入成功，$failureCount 筆失敗（首個錯誤：$cause）';
}
