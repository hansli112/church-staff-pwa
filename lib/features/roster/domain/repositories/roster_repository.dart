import '../entities/event_option.dart';
import '../entities/service_roster.dart';

abstract class RosterRepository {
  Future<List<ServiceRoster>> getUpcomingRosters();
  Future<void> updateRoster(ServiceRoster roster);
  Future<Map<ServiceType, List<String>>> getServiceTemplates();
  Future<void> updateServiceTemplates(Map<ServiceType, List<String>> templates);
  Future<List<EventOption>> getEventOptions();
  Future<void> updateEventOptions(List<EventOption> options);
}
