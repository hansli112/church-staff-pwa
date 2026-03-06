import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/event_option.dart';
import '../../domain/entities/service_roster.dart';
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
    // 取得當前日期，只撈取未來或今天的服事表 (例如本季到下一季)
    // 這裡為了簡單，先撈取所有資料，之後可以優化成只撈需要的區間
    try {
      final snapshot = await _rostersCollection
          .orderBy('date') // 依照日期排序
          .get();

      if (snapshot.docs.isNotEmpty) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final endDate = _nextQuarterEndDate(now);

        final existingRosters = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return _fromFirestore(data, doc.id);
        }).toList();
        final existingIds = existingRosters.map((r) => r.id).toSet();

        final templates = await getServiceTemplates();
        final generated = _generateQuarterRosters(templates);
        final missing = generated
            .where((roster) => !existingIds.contains(roster.id))
            .toList();

        if (missing.isNotEmpty) {
          final batch = _firestore.batch();
          for (final roster in missing) {
            final docRef = _rostersCollection.doc(roster.id);
            batch.set(docRef, _toFirestore(roster));
          }
          await batch.commit();
        }

        final combined = [...existingRosters, ...missing].where((roster) {
          return !roster.date.isBefore(today) && !roster.date.isAfter(endDate);
        }).toList();

        combined.sort((a, b) {
          final dateCompare = a.date.compareTo(b.date);
          if (dateCompare != 0) return dateCompare;
          return a.type.toString().compareTo(b.type.toString());
        });

        return combined;
      }

      final templates = await getServiceTemplates();
      final generated = _generateQuarterRosters(templates);
      if (generated.isEmpty) {
        return [];
      }

      final batch = _firestore.batch();
      for (final roster in generated) {
        final docId = _makeRosterId(roster.date, roster.type);
        final docRef = _rostersCollection.doc(docId);
        batch.set(docRef, _toFirestore(roster.copyWith(id: docId)));
      }
      await batch.commit();
      return generated.map((r) {
        final id = _makeRosterId(r.date, r.type);
        return r.copyWith(id: id);
      }).toList();
    } catch (e) {
      log('Get Rosters Error: $e');
      return [];
    }
  }

  @override
  Future<void> updateRoster(ServiceRoster roster) async {
    try {
      // 確保將 id 寫入 document id
      await _rostersCollection.doc(roster.id).set(_toFirestore(roster));
    } catch (e) {
      log('Update Roster Error: $e');
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
    } catch (e) {
      log('Get Templates Error: $e');
      return {};
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
    } catch (e) {
      log('Update Templates Error: $e');
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
    } catch (e) {
      log('Get Event Options Error: $e');
      return _defaultEventOptions();
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
    } catch (e) {
      log('Update Event Options Error: $e');
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
      'duties': roster.duties
          .map(
            (d) => {
              'role': d.role,
              'people': d.people,
              'peopleOrder': d.peopleOrder,
              'personIdsByName': d.personIdsByName,
              'assignedUserIds': d.assignedUserIds,
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
      for (final type in ServiceType.values) {
        final roles = templates[type] ?? [];
        final duties = roles
            .map((role) => RosterEntry(role: role, people: ['待定']))
            .toList();
        final serviceDate = _serviceDate(cursor, type);
        final events = _defaultEventsForDate(serviceDate, type);
        allRosters.add(
          ServiceRoster(
            id: _makeRosterId(serviceDate, type),
            date: serviceDate,
            type: type,
            serviceName: _serviceNameForType(type),
            duties: duties,
            specialEvents: events,
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

  List<String> _defaultEventsForDate(DateTime date, ServiceType type) {
    return const [];
  }

  DateTime _serviceDate(DateTime sunday, ServiceType type) {
    if (type == ServiceType.youth) {
      return sunday.subtract(const Duration(days: 1));
    }
    return sunday;
  }
}
