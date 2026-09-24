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
      color: rawColor is int ? rawColor : 0xFFD97706,
    );
  }
}

/// 活動清單裡找不到、服事表也沒自己指定顏色的活動用這個色。
const int fallbackEventColor = 0xFF7F8C8D;

/// 活動可以選的顏色。活動設定頁的色盤跟匯入時自動配色用同一份，
/// 不然自動配出來的顏色會是設定頁點不回去的顏色。
///
/// Tailwind 的 600 色階，照色相排成兩排各五個（見 EventColorPicker）。標籤
/// 是拿這個顏色當字色、再鋪一層 12% 的同色底，所以要同一個深淺：Google
/// 日曆那套的黃、粉當字色幾乎看不見，最早用的 Flat UI 那套也偏淡。
/// 2026-09-24 換過一次，線上活動清單裡的舊色碼一起換成了最接近的新色。
///
/// 沒有灰色：灰色是「沒設顏色」的 [fallbackEventColor]，選了它的活動看起來
/// 就像沒設。
const List<int> eventColorPalette = [
  0xFFDC2626, // red
  0xFFEA580C, // orange
  0xFFD97706, // amber
  0xFF16A34A, // green
  0xFF0D9488, // teal
  0xFF0284C7, // sky
  0xFF2563EB, // blue
  0xFF4F46E5, // indigo
  0xFF7C3AED, // violet
  0xFFDB2777, // pink
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
