/// 首頁「本季服事」涵蓋的日期範圍。
///
/// 只看本季的話，季末最後幾天常常一場聚會都沒有（例如 9/28–9/30），首頁就
/// 顯示「本季尚無排到服事」，但下一季的服事表早就排好了。所以最後兩週一併
/// 列出下一季；服事表在季末那個月本來就會讀到下一季底。
class SeasonWindow {
  const SeasonWindow({
    required this.start,
    required this.end,
    required this.includesNextQuarter,
  });

  final DateTime start;
  final DateTime end;
  final bool includesNextQuarter;

  String get title => includesNextQuarter ? '本季與下季服事' : '本季服事';

  String get emptyText => includesNextQuarter ? '本季與下季尚無排到服事' : '本季尚無排到服事';
}

/// [today] 是教會時區的日期（見 ChurchTime.today）。
SeasonWindow seasonWindow(DateTime today) {
  final startMonth = ((today.month - 1) ~/ 3) * 3 + 1;
  final start = DateTime.utc(today.year, startMonth, 1);
  final quarterEnd = DateTime.utc(today.year, startMonth + 3, 0);
  final day = DateTime.utc(today.year, today.month, today.day);
  if (quarterEnd.difference(day).inDays >= 14) {
    return SeasonWindow(
      start: start,
      end: quarterEnd,
      includesNextQuarter: false,
    );
  }
  return SeasonWindow(
    start: start,
    end: DateTime.utc(today.year, startMonth + 6, 0),
    includesNextQuarter: true,
  );
}
