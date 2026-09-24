import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/event_option.dart';
import '../../domain/entities/service_roster.dart';
import 'package:church_staff_pwa/core/types/service_type.dart';
import '../../domain/repositories/roster_repository.dart';
import '../../domain/staff_order.dart';
import '../../domain/roster_schedule.dart';
import '../roster_document.dart';
import '../../../../core/time/church_time.dart';

class FirestoreRosterRepository implements RosterRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference get _rostersCollection =>
      _firestore.collection('rosters');
  DocumentReference get _templatesDoc =>
      _firestore.collection('settings').doc('roster_templates');
  DocumentReference get _eventOptionsDoc =>
      _firestore.collection('settings').doc('event_options');

  // 不放在 settings/ 底下：那裡只有 admin 能寫，而同工排序是各崇拜的編輯
  // 者在選人視窗裡拖出來的。一個崇拜一份文件，rules 才能照文件 id 判斷是
  // 不是他的牧區（見 firestore.rules 的 staff_orders）。
  CollectionReference get _staffOrdersCollection =>
      _firestore.collection('staff_orders');

  @override
  Future<List<ServiceRoster>> getUpcomingRosters() async {
    // 純讀路徑。不執行任何 backfill 寫入。
    // backfill 已移至 ensureQuarterRosters()，只由 admin 在進入編輯畫面時觸發。
    try {
      final now = ChurchTime.now();
      final fetchFrom = ChurchTime.dateOnly(
        now,
      ).subtract(const Duration(days: 7));
      final fetchFromTimestamp = Timestamp.fromDate(fetchFrom);

      final snapshot = await _rostersCollection
          .where('date', isGreaterThanOrEqualTo: fetchFromTimestamp)
          .orderBy('date')
          .get();

      return _filterAndSortRosters(snapshot.docs, now);
    } catch (e, st) {
      // 一定要往上丟：吞掉錯誤回傳空 list 的話，permission-denied 或離線
      // 在畫面上會變成「此類別目前沒有服事資訊」，使用者看不到錯誤也沒有
      // 重試鈕。要不要降級成 cache 資料由 RosterProvider 決定。
      log('Get rosters failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  @override
  Future<List<ServiceRoster>> getUpcomingRostersFromCache() async {
    // 從 IndexedDB 讀取。不打網路，約 50-150ms。
    // 若 cache 尚未建立（首次開啟），SDK 丟 unavailable / failed-precondition，
    // catch 後回傳空 list，讓呼叫端降級到 server fetch。
    try {
      final now = ChurchTime.now();
      final fetchFrom = ChurchTime.dateOnly(
        now,
      ).subtract(const Duration(days: 7));
      final fetchFromTimestamp = Timestamp.fromDate(fetchFrom);

      final snapshot = await _rostersCollection
          .where('date', isGreaterThanOrEqualTo: fetchFromTimestamp)
          .orderBy('date')
          .get(const GetOptions(source: Source.cache));

      return _filterAndSortRosters(snapshot.docs, now);
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable' || e.code == 'failed-precondition') {
        // cache-miss 或持久化尚未就緒：視為空
        return const [];
      }
      rethrow;
    }
  }

  @override
  Future<void> ensureQuarterRosters(List<ServiceType> allowedTypes) async {
    // 確保本季 + 下季的預定 roster 都已存在於 Firestore（缺的補寫）。
    // 只補 allowedTypes 涵蓋的聚會別 —— 其餘的呼叫者無權寫，混進同一個 batch
    // 會讓整批被 rules 拒絕。真正的強制點仍在 firestore.rules。
    if (allowedTypes.isEmpty) return;
    try {
      final templates = await getServiceTemplates();
      final now = ChurchTime.now();
      final quarterStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
      // 包含跨季的同一週與 UTC 偏移，避免更換星期後在同一週產生第二場。
      final fetchFrom = DateTime.utc(
        now.year,
        quarterStartMonth,
        1,
      ).subtract(const Duration(days: 7));
      final snapshot = await _rostersCollection
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(fetchFrom))
          .get();
      final existing = snapshot.docs.map(
        (doc) =>
            rosterFromFirestore(doc.data() as Map<String, dynamic>, doc.id),
      );
      final missing = planQuarterRosters(
        now: now,
        types: allowedTypes,
        templates: templates,
        existing: existing,
      );
      // 每個候選週的七個日期都在 transaction 內讀取，避免兩個使用不同星期
      // 設定的客戶端同時建表。每批最多 140 個讀取、20 個寫入；先全部讀再寫。
      for (var start = 0; start < missing.length; start += 20) {
        final chunk = missing.skip(start).take(20).toList();
        final weeks = [
          for (final roster in chunk)
            rosterWeekDocumentIds(roster.type, roster.date),
        ];
        await _firestore.runTransaction((transaction) async {
          final snapshots = await Future.wait(
            weeks
                .expand((ids) => ids)
                .toSet()
                .map((id) => transaction.get(_rostersCollection.doc(id))),
          );
          final occupiedIds = {
            for (final snapshot in snapshots)
              if (snapshot.exists) snapshot.id,
          };
          for (var i = 0; i < chunk.length; i++) {
            if (!weeks[i].any(occupiedIds.contains)) {
              transaction.set(
                _rostersCollection.doc(chunk[i].id),
                rosterToFirestore(chunk[i]),
              );
            }
          }
        });
      }
    } catch (e, st) {
      log('ensureQuarterRosters failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// 共用的 snapshot → filter → sort 邏輯（供 getUpcomingRosters 與
  /// getUpcomingRostersFromCache 兩個讀路徑重用）。
  List<ServiceRoster> _filterAndSortRosters(
    List<QueryDocumentSnapshot<Object?>> docs,
    DateTime now,
  ) {
    if (docs.isEmpty) return const [];
    final today = ChurchTime.dateOnly(now);
    final endDate = rosterQuarterEnd(now);

    final rosters = docs
        .map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return rosterFromFirestore(data, doc.id);
        })
        .where((r) => !r.date.isBefore(today) && !r.date.isAfter(endDate))
        .toList();

    rosters.sort((a, b) {
      final dateCompare = a.date.compareTo(b.date);
      if (dateCompare != 0) return dateCompare;
      return a.type.toString().compareTo(b.type.toString());
    });

    return rosters;
  }

  @override
  Future<void> updateRoster(ServiceRoster roster) async {
    try {
      // 確保將 id 寫入 document id
      await _rostersCollection.doc(roster.id).set(rosterToFirestore(roster));
    } catch (e, st) {
      log('Update roster failed', error: e, stackTrace: st);
      throw Exception('更新服事表失敗: $e');
    }
  }

  @override
  Future<void> updateRostersAtomically(List<ServiceRoster> rosters) async {
    if (rosters.isEmpty) return;
    try {
      final batch = _firestore.batch();
      for (final roster in rosters) {
        batch.set(_rostersCollection.doc(roster.id), rosterToFirestore(roster));
      }
      await batch.commit();
    } catch (e, st) {
      log('Update rosters atomically failed', error: e, stackTrace: st);
      // 刻意不像 updateRoster 那樣包成 Exception('更新服事表失敗: $e')：包過之後
      // mapErrorToUserMessage 認不出 FirebaseException 的 code，permission-denied
      // 會變成「操作失敗，請稍後再試」，使用者不知道是權限問題還是網路問題。
      rethrow;
    }
  }

  @override
  Future<Map<ServiceType, List<String>>> getServiceTemplates() async {
    try {
      final doc = await _templatesDoc.get();
      if (!doc.exists) {
        // 如果沒有設定，預設為空，讓使用者自行設定
        return {for (final type in ServiceType.values) type: []};
      }

      final data = doc.data() as Map<String, dynamic>;
      return data.map((key, value) {
        final type = ServiceType.fromName(key);
        return MapEntry(type, List<String>.from(value));
      });
    } catch (e, st) {
      log('Get service templates failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  @override
  Future<void> updateServiceTemplates(
    Map<ServiceType, List<String>> templates,
  ) async {
    try {
      final data = templates.map((key, value) {
        return MapEntry(key.name, value);
      });
      await _templatesDoc.set(data, SetOptions(merge: true));
    } catch (e, st) {
      log('Update service templates failed', error: e, stackTrace: st);
      throw Exception('更新樣板失敗: $e');
    }
  }

  @override
  Future<Map<ServiceType, List<EventOption>>> getEventOptions() async {
    try {
      final doc = await _eventOptionsDoc.get();
      if (!doc.exists) {
        return _defaultEventOptions();
      }

      final data = doc.data() as Map<String, dynamic>;
      final Map<ServiceType, List<EventOption>> result = {};
      for (final type in ServiceType.values) {
        final key = type.name;
        final rawList = data[key];
        if (rawList is List) {
          result[type] = _parseEventOptionsList(rawList);
        } else {
          result[type] = const <EventOption>[];
        }
      }
      return result;
    } catch (e, st) {
      log('Get event options failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  @override
  Future<void> updateEventOptions(
    Map<ServiceType, List<EventOption>> options,
  ) async {
    try {
      final data = options.map((key, value) {
        final cleaned = value
            .map((e) => e.copyWith(name: e.name.trim()))
            .where((e) => e.name.isNotEmpty)
            .map((e) => e.toJson())
            .toList();
        return MapEntry(key.name, cleaned);
      });
      await _eventOptionsDoc.set(data, SetOptions(merge: true));
    } catch (e, st) {
      log('Update event options failed', error: e, stackTrace: st);
      throw Exception('更新事件選項失敗: $e');
    }
  }

  Map<ServiceType, List<EventOption>> _defaultEventOptions() {
    return {for (final type in ServiceType.values) type: const <EventOption>[]};
  }

  List<EventOption> _parseEventOptionsList(List<dynamic> items) {
    return items
        .map((item) {
          if (item is String) {
            return EventOption(name: item, color: 0xFFD97706);
          }
          if (item is Map) {
            return EventOption.fromJson(Map<String, dynamic>.from(item));
          }
          return const EventOption(name: '', color: 0xFFD97706);
        })
        .where((e) => e.name.trim().isNotEmpty)
        .toList();
  }

  @override
  Future<Map<ServiceType, StaffOrder>> getStaffOrders() async {
    try {
      final snapshot = await _staffOrdersCollection.get();
      final result = <ServiceType, StaffOrder>{};
      for (final doc in snapshot.docs) {
        final type = ServiceType.values
            .where((e) => e.name == doc.id)
            .firstOrNull;
        if (type == null) continue;
        result[type] = StaffOrder.fromJson(doc.data() as Map<String, dynamic>);
      }
      return result;
    } catch (e, st) {
      log('Get staff orders failed', error: e, stackTrace: st);
      rethrow;
    }
  }

  @override
  Future<void> updateStaffRankings(
    ServiceType type,
    Map<String, List<String>?> changes,
  ) async {
    if (changes.isEmpty) return;
    try {
      // merge 寫入巢狀 map 只動提到的 key：別人剛改過的其他服事項目不會被
      // 這台裝置手上那份舊的蓋回去。用 set 而不是 update，文件還不存在時
      // 才建得出來；key 不經過欄位路徑解析，服事項目名稱有「.」也沒關係。
      await _staffOrdersCollection.doc(type.name).set({
        'roles': {
          for (final entry in changes.entries)
            entry.key: entry.value ?? FieldValue.delete(),
        },
      }, SetOptions(merge: true));
    } catch (e, st) {
      log('Update staff order failed', error: e, stackTrace: st);
      // 不包成 Exception：包過之後 mapErrorToUserMessage 認不出
      // permission-denied（見 updateRostersAtomically）。
      rethrow;
    }
  }
}
