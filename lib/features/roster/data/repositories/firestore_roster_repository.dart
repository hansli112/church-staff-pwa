import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/event_option.dart';
import '../../domain/entities/service_roster.dart';
import 'package:church_staff_pwa/core/types/service_type.dart';
import '../../domain/repositories/roster_repository.dart';

class FirestoreRosterRepository implements RosterRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference get _rostersCollection =>
      _firestore.collection('rosters');
  DocumentReference get _templatesDoc =>
      _firestore.collection('settings').doc('roster_templates');
  DocumentReference get _eventOptionsDoc =>
      _firestore.collection('settings').doc('event_options');

  @override
  Future<List<ServiceRoster>> getUpcomingRosters() async {
    // 純讀路徑。不執行任何 backfill 寫入。
    // backfill 已移至 ensureQuarterRosters()，只由 admin 在進入編輯畫面時觸發。
    try {
      final now = DateTime.now();
      final fetchFrom = DateTime(
        now.year,
        now.month,
        now.day,
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
      final now = DateTime.now();
      final fetchFrom = DateTime(
        now.year,
        now.month,
        now.day,
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
      final generated = _generateQuarterRosters(templates, allowedTypes);
      if (generated.isEmpty) return;

      // Scope the existence check to the current quarter onwards so that
      // historical data does not cause a full-collection scan.
      final now = DateTime.now();
      final quarterStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
      final quarterStart = DateTime(now.year, quarterStartMonth, 1);
      final snapshot = await _rostersCollection
          .where(
            'date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(quarterStart),
          )
          .get();
      final existingIds = snapshot.docs.map((d) => d.id).toSet();

      final missing = generated
          .where((r) => !existingIds.contains(r.id))
          .toList();
      if (missing.isEmpty) return;

      final batch = _firestore.batch();
      for (final roster in missing) {
        batch.set(_rostersCollection.doc(roster.id), _toFirestore(roster));
      }
      await batch.commit();
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
    final today = DateTime(now.year, now.month, now.day);
    final endDate = _nextQuarterEndDate(now);

    final rosters = docs
        .map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return _fromFirestore(data, doc.id);
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
      await _rostersCollection.doc(roster.id).set(_toFirestore(roster));
    } catch (e, st) {
      log('Update roster failed', error: e, stackTrace: st);
      throw Exception('更新服事表失敗: $e');
    }
  }

  @override
  Future<Map<ServiceType, List<String>>> getServiceTemplates() async {
    try {
      final doc = await _templatesDoc.get();
      if (!doc.exists) {
        // 如果沒有設定，預設為空，讓使用者自行設定
        return {
          ServiceType.sundayService: [],
          ServiceType.youth: [],
          ServiceType.children: [],
        };
      }

      final data = doc.data() as Map<String, dynamic>;
      return data.map((key, value) {
        // key is string like 'sundayService', convert back to enum
        final type = ServiceType.values.firstWhere(
          (e) => e.toString().split('.').last == key,
          orElse: () => ServiceType.sundayService,
        );
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
        return MapEntry(key.toString().split('.').last, value);
      });
      await _templatesDoc.set(data);
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
        final key = type.toString().split('.').last;
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
        return MapEntry(key.toString().split('.').last, cleaned);
      });
      await _eventOptionsDoc.set(data);
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
            return EventOption(name: item, color: 0xFFF39C12);
          }
          if (item is Map) {
            return EventOption.fromJson(Map<String, dynamic>.from(item));
          }
          return const EventOption(name: '', color: 0xFFF39C12);
        })
        .where((e) => e.name.trim().isNotEmpty)
        .toList();
  }

  // Helper: Convert ServiceRoster to Map for Firestore
  Map<String, dynamic> _toFirestore(ServiceRoster roster) {
    return {
      'date': Timestamp.fromDate(roster.date),
      'type': roster.type.toString().split('.').last,
      'serviceName': roster.serviceName,
      'specialEvents': roster.specialEvents,
      'customEventColors': Map<String, dynamic>.from(roster.customEventColors),
      'duties': roster.duties
          .map(
            (d) => {
              'role': d.role,
              'people': d.people,
              'peopleOrder': d.peopleOrder,
              'personIdsByName': d.personIdsByName,
            },
          )
          .toList(),
    };
  }

  // Helper: Convert Map from Firestore to ServiceRoster

  Map<String, String> _parsePersonIdsByName(dynamic raw) {
    if (raw is! Map) return const {};
    final result = <String, String>{};
    raw.forEach((key, value) {
      if (key is! String || value is! String) return;
      final name = key.trim();
      final uid = value.trim();
      if (name.isEmpty || uid.isEmpty) return;
      result[name] = uid;
    });
    return result;
  }

  ServiceRoster _fromFirestore(Map<String, dynamic> data, String id) {
    return ServiceRoster(
      id: id,
      date: (data['date'] as Timestamp).toDate(),
      type: ServiceType.values.firstWhere(
        (e) => e.toString().split('.').last == data['type'],
        orElse: () => ServiceType.sundayService,
      ),
      serviceName: data['serviceName'] as String? ?? '',
      specialEvents: List<String>.from(data['specialEvents'] ?? const []),
      customEventColors: () {
        final raw = data['customEventColors'];
        if (raw is! Map) return <String, int>{};
        return Map<String, int>.fromEntries(
          raw.entries
              .where((e) => e.key is String && e.value is num)
              .map((e) => MapEntry(e.key as String, (e.value as num).toInt())),
        );
      }(),
      duties:
          (data['duties'] as List<dynamic>?)?.map((item) {
            final d = item as Map<String, dynamic>;
            return RosterEntry(
              role: d['role'] as String,
              people: List<String>.from(d['people'] ?? []),
              peopleOrder: List<String>.from(d['peopleOrder'] ?? const []),
              personIdsByName: _parsePersonIdsByName(d['personIdsByName']),
            );
          }).toList() ??
          [],
    );
  }

  String _makeRosterId(DateTime date, ServiceType type) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    final typeKey = type.toString().split('.').last;
    return '$y$m${d}_$typeKey';
  }

  String _serviceNameForType(ServiceType type) {
    switch (type) {
      case ServiceType.sundayService:
        return '主日崇拜';
      case ServiceType.youth:
        return '青年崇拜';
      case ServiceType.children:
        return '兒童主日學';
    }
  }

  List<ServiceRoster> _generateQuarterRosters(
    Map<ServiceType, List<String>> templates,
    List<ServiceType> allowedTypes,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final quarterStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
    final targetEndDate = _nextQuarterEndDate(now);

    DateTime cursor = DateTime(now.year, quarterStartMonth, 1);
    while (cursor.weekday != DateTime.sunday) {
      cursor = cursor.add(const Duration(days: 1));
    }

    final List<ServiceRoster> allRosters = [];
    while (!cursor.isAfter(targetEndDate)) {
      for (final type in allowedTypes) {
        final roles = templates[type] ?? [];
        final duties = roles
            .map((role) => RosterEntry(role: role, people: ['待定']))
            .toList();
        final serviceDate = _serviceDate(cursor, type);
        allRosters.add(
          ServiceRoster(
            id: _makeRosterId(serviceDate, type),
            date: serviceDate,
            type: type,
            serviceName: _serviceNameForType(type),
            duties: duties,
          ),
        );
      }
      cursor = cursor.add(const Duration(days: 7));
    }

    return allRosters.where((r) => !r.date.isBefore(today)).toList();
  }

  DateTime _nextQuarterEndDate(DateTime now) {
    final quarterStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
    final isLastMonthOfQuarter = now.month == (quarterStartMonth + 2);
    final targetEndMonthRaw = isLastMonthOfQuarter
        ? quarterStartMonth + 5
        : quarterStartMonth + 2;
    final targetEndYear = now.year + ((targetEndMonthRaw - 1) ~/ 12);
    final targetEndMonth = ((targetEndMonthRaw - 1) % 12) + 1;
    return DateTime(targetEndYear, targetEndMonth + 1, 0);
  }

  DateTime _serviceDate(DateTime sunday, ServiceType type) {
    if (type == ServiceType.youth) {
      return sunday.subtract(const Duration(days: 1));
    }
    return sunday;
  }
}
