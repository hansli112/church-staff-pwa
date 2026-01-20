import '../entities/service_roster.dart';

abstract class RosterRepository {
  Future<List<ServiceRoster>> getUpcomingRosters();
}
