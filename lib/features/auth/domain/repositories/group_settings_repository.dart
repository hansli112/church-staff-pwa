import '../../../roster/domain/entities/service_roster.dart';

abstract class GroupSettingsRepository {
  Future<Map<ServiceType, List<String>>> getSmallGroupTemplates();
  Future<void> updateSmallGroupTemplates(Map<ServiceType, List<String>> templates);
}
