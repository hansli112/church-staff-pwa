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
