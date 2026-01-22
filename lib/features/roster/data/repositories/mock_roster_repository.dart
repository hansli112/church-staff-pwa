import '../../domain/entities/service_roster.dart';
import '../../domain/repositories/roster_repository.dart';

class MockRosterRepository implements RosterRepository {
  List<ServiceRoster> _cachedRosters = [];
  Map<ServiceType, List<String>> _templates = {
    ServiceType.sundayService: ['領會', '講員', '司琴', '音控', '招待'],
    ServiceType.youth: ['敬拜主領', '吉他', '木箱鼓', 'PPT', '小組長'],
    ServiceType.children: ['合班老師', '司琴', '分班(大)', '分班(小)', '點心'],
  };

  @override
  Future<Map<ServiceType, List<String>>> getServiceTemplates() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return Map.from(_templates);
  }

  @override
  Future<void> updateServiceTemplates(Map<ServiceType, List<String>> templates) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _templates = Map.from(templates);
  }

  @override
  Future<List<ServiceRoster>> getUpcomingRosters() async {
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (_cachedRosters.isNotEmpty) {
      return _cachedRosters;
    }

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

    // Filter and cache
    _cachedRosters = allRosters.where((roster) => !roster.date.isBefore(today)).toList();
    return _cachedRosters;
  }

  @override
  Future<void> updateRoster(ServiceRoster roster) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final index = _cachedRosters.indexWhere((r) => r.id == roster.id);
    if (index != -1) {
      _cachedRosters[index] = roster;
    } else {
      throw Exception('Roster not found');
    }
  }

  ServiceRoster _generateRoster(int id, DateTime date, ServiceType type) {
    String serviceName = '';
    switch (type) {
      case ServiceType.sundayService: serviceName = '主日崇拜'; break;
      case ServiceType.youth: serviceName = '青年崇拜'; break;
      case ServiceType.children: serviceName = '兒童主日學'; break;
    }

    // 如果模板存在，使用模板產生空白名單
    if (_templates.containsKey(type)) {
      final roles = _templates[type] ?? [];
      final duties = roles.map((role) => RosterEntry(role: role, people: ['待定'])).toList();
      
      return ServiceRoster(
        id: id.toString(),
        date: date,
        type: type,
        serviceName: serviceName,
        duties: duties,
      );
    }

    // Fallback: 如果沒有模板（初始化前），使用舊的硬編碼邏輯
    List<RosterEntry> duties = [];

    switch (type) {
      case ServiceType.sundayService:
        duties = [
          RosterEntry(role: '領會', people: ['張弟兄']),
          RosterEntry(role: '講員', people: ['王牧師']),
          RosterEntry(role: '司琴', people: ['李姊妹']),
          RosterEntry(role: '音控', people: ['陳弟兄']),
          RosterEntry(role: '招待', people: ['林弟兄', '黃姊妹']), // 範例：多人
        ];
        break;
      case ServiceType.youth:
        duties = [
          RosterEntry(role: '敬拜主領', people: ['Kevin']),
          RosterEntry(role: '吉他', people: ['Jason']),
          RosterEntry(role: '木箱鼓', people: ['Eric']),
          RosterEntry(role: 'PPT', people: ['Sarah']),
          RosterEntry(role: '小組長', people: ['David']),
        ];
        break;
      case ServiceType.children:
        duties = [
          RosterEntry(role: '合班老師', people: ['陳媽媽']),
          RosterEntry(role: '司琴', people: ['小美']),
          RosterEntry(role: '分班(大)', people: ['王叔叔']),
          RosterEntry(role: '分班(小)', people: ['林阿姨']),
          RosterEntry(role: '點心', people: ['吳奶奶']),
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
