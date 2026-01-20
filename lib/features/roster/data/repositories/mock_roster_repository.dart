import '../../domain/entities/service_roster.dart';
import '../../domain/repositories/roster_repository.dart';

class MockRosterRepository implements RosterRepository {
  @override
  Future<List<ServiceRoster>> getUpcomingRosters() async {
    await Future.delayed(const Duration(milliseconds: 500));
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final quarterStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
    final quarterEndMonth = quarterStartMonth + 2;

    List<ServiceRoster> allRosters = [];
    
    DateTime cursor = DateTime(now.year, quarterStartMonth, 1);
    while (cursor.weekday != DateTime.sunday) {
      cursor = cursor.add(const Duration(days: 1));
    }

    int idCounter = 1;
    while (cursor.month <= quarterEndMonth && cursor.year == now.year) {
      // 針對每一週，產生三種聚會的資料
      allRosters.add(_generateRoster(idCounter++, cursor, ServiceType.sundayService));
      allRosters.add(_generateRoster(idCounter++, cursor, ServiceType.youth));
      allRosters.add(_generateRoster(idCounter++, cursor, ServiceType.children));
      
      cursor = cursor.add(const Duration(days: 7));
    }

    return allRosters.where((roster) => !roster.date.isBefore(today)).toList();
  }

  ServiceRoster _generateRoster(int id, DateTime date, ServiceType type) {
    // 根據不同聚會類型，給予不同的職位與假名單
    String serviceName = '';
    List<RosterEntry> duties = [];

    switch (type) {
      case ServiceType.sundayService:
        serviceName = '主日崇拜';
        duties = [
          RosterEntry(role: '領會', personName: '張弟兄'),
          RosterEntry(role: '講員', personName: '王牧師'),
          RosterEntry(role: '司琴', personName: '李姊妹'),
          RosterEntry(role: '音控', personName: '陳弟兄'),
          RosterEntry(role: '招待', personName: '林弟兄'),
        ];
        break;
      case ServiceType.youth:
        serviceName = '青年崇拜';
        duties = [
          RosterEntry(role: '敬拜主領', personName: 'Kevin'),
          RosterEntry(role: '吉他', personName: 'Jason'),
          RosterEntry(role: '木箱鼓', personName: 'Eric'),
          RosterEntry(role: 'PPT', personName: 'Sarah'),
          RosterEntry(role: '小組長', personName: 'David'),
        ];
        break;
      case ServiceType.children:
        serviceName = '兒童主日學';
        duties = [
          RosterEntry(role: '合班老師', personName: '陳媽媽'),
          RosterEntry(role: '司琴', personName: '小美'),
          RosterEntry(role: '分班(大)', personName: '王叔叔'),
          RosterEntry(role: '分班(小)', personName: '林阿姨'),
          RosterEntry(role: '點心', personName: '吳奶奶'),
        ];
        break;
    }

    return ServiceRoster(
      id: id.toString(),
      date: date,
      type: type,
      serviceName: serviceName,
      duties: duties,
    );
  }
}
