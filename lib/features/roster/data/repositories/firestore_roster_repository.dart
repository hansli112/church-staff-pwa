import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/service_roster.dart';
import '../../domain/repositories/roster_repository.dart';

class FirestoreRosterRepository implements RosterRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference get _rostersCollection => _firestore.collection('rosters');
  DocumentReference get _templatesDoc => _firestore.collection('settings').doc('roster_templates');

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

        return snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return _fromFirestore(data, doc.id);
        }).where((roster) {
          return !roster.date.isBefore(today) && !roster.date.isAfter(endDate);
        }).toList();
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
      print('Get Rosters Error: $e');
      return [];
    }
  }

  @override
  Future<void> updateRoster(ServiceRoster roster) async {
    try {
      // 確保將 id 寫入 document id
      await _rostersCollection.doc(roster.id).set(_toFirestore(roster));
    } catch (e) {
      print('Update Roster Error: $e');
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
      print('Get Templates Error: $e');
      return {};
    }
  }

  @override
  Future<void> updateServiceTemplates(Map<ServiceType, List<String>> templates) async {
    try {
      final data = templates.map((key, value) {
        return MapEntry(key.toString().split('.').last, value);
      });
      await _templatesDoc.set(data);
    } catch (e) {
      print('Update Templates Error: $e');
      throw Exception('更新樣板失敗: $e');
    }
  }

  // Helper: Convert ServiceRoster to Map for Firestore
  Map<String, dynamic> _toFirestore(ServiceRoster roster) {
    return {
      'date': Timestamp.fromDate(roster.date),
      'type': roster.type.toString().split('.').last,
      'serviceName': roster.serviceName,
      'duties': roster.duties.map((d) => {
        'role': d.role,
        'people': d.people,
      }).toList(),
    };
  }

  // Helper: Convert Map from Firestore to ServiceRoster
  ServiceRoster _fromFirestore(Map<String, dynamic> data, String id) {
    return ServiceRoster(
      id: id,
      date: (data['date'] as Timestamp).toDate(),
      type: ServiceType.values.firstWhere(
        (e) => e.toString().split('.').last == data['type'],
        orElse: () => ServiceType.sundayService,
      ),
      serviceName: data['serviceName'] as String? ?? '',
      duties: (data['duties'] as List<dynamic>?)?.map((item) {
        final d = item as Map<String, dynamic>;
        return RosterEntry(
          role: d['role'] as String,
          people: List<String>.from(d['people'] ?? []),
        );
      }).toList() ?? [],
    );
  }

  String _makeRosterId(DateTime date, ServiceType type) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    final typeKey = type.toString().split('.').last;
    return '${y}${m}${d}_$typeKey';
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
        allRosters.add(ServiceRoster(
          id: _makeRosterId(cursor, type),
          date: cursor,
          type: type,
          serviceName: _serviceNameForType(type),
          duties: duties,
        ));
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
}
