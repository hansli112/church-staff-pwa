import 'package:church_staff_pwa/core/types/service_type.dart';

abstract class GroupSettingsRepository {
  Future<Map<ServiceType, List<String>>> getSmallGroupTemplates();
  Future<void> updateSmallGroupTemplates(Map<ServiceType, List<String>> templates);
}
