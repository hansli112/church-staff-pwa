class EventOption {
  final String name;
  final int color;

  const EventOption({required this.name, required this.color});

  EventOption copyWith({String? name, int? color}) {
    return EventOption(name: name ?? this.name, color: color ?? this.color);
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'color': color};
  }

  static EventOption fromJson(Map<String, dynamic> json) {
    final rawName = json['name'];
    final rawColor = json['color'];
    return EventOption(
      name: rawName is String ? rawName : '',
      color: rawColor is int ? rawColor : 0xFFF39C12,
    );
  }
}

/// 活動清單裡找不到、服事表也沒自己指定顏色的活動用這個色。
const int fallbackEventColor = 0xFF7F8C8D;

/// 活動可以選的顏色。活動設定頁的色盤跟匯入時自動配色用同一份，
/// 不然自動配出來的顏色會是設定頁點不回去的顏色。
const List<int> eventColorPalette = [
  0xFFF39C12, // amber
  0xFF27AE60, // green
  0xFF3498DB, // blue
  0xFF9B59B6, // purple
  0xFFE74C3C, // red
  fallbackEventColor, // gray
];

/// 幫新活動挑一個顏色：這個崇拜目前用得最少的那個，同樣少就照色盤順序。
///
/// 全部都用過時也不會跟前一個撞色 —— 挑最少的而不是固定第一個，是為了讓
/// 同一季一次加進來的幾個活動彼此分得開。
int pickEventColor(List<EventOption> existing) {
  final useCount = <int, int>{for (final color in eventColorPalette) color: 0};
  for (final option in existing) {
    if (useCount.containsKey(option.color)) {
      useCount[option.color] = useCount[option.color]! + 1;
    }
  }
  var best = eventColorPalette.first;
  for (final color in eventColorPalette) {
    if (useCount[color]! < useCount[best]!) best = color;
  }
  return best;
}
