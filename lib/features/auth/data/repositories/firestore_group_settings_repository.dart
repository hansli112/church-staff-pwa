import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/repositories/group_settings_repository.dart';
import 'package:church_staff_pwa/core/types/service_type.dart';

class FirestoreGroupSettingsRepository implements GroupSettingsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DocumentReference get _templatesDoc =>
      _firestore.collection('settings').doc('small_group_templates');

  @override
  Future<Map<ServiceType, List<String>>> getSmallGroupTemplates() async {
    try {
      final doc = await _templatesDoc.get();
      if (!doc.exists) {
        return {for (final type in ServiceType.values) type: []};
      }

      final data = doc.data() as Map<String, dynamic>;
      return data.map((key, value) {
        final type = ServiceType.fromName(key);
        return MapEntry(type, List<String>.from(value));
      });
    } catch (e) {
      log('Get Small Groups Error: $e');
      return {};
    }
  }

  @override
  Future<void> updateSmallGroupTemplates(
    Map<ServiceType, List<String>> templates,
  ) async {
    try {
      final data = templates.map((key, value) {
        return MapEntry(key.name, value);
      });
      await _templatesDoc.set(data, SetOptions(merge: true));
    } catch (e) {
      log('Update Small Groups Error: $e');
      throw Exception('更新小組設定失敗: $e');
    }
  }
}
