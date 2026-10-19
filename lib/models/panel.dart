class Panel {
  final String tag;
  final String loc;
  final String type;
  final double? latitude;
  final double? longitude;
  final String? lastInspectedAt;
  final String? color;
  final String? note;

  Panel({
    required this.tag,
    required this.loc,
    required this.type,
    this.latitude,
    this.longitude,
    this.lastInspectedAt,
    this.color,
    this.note,
  });

  factory Panel.fromJson(Map<String, dynamic> json) {
    return Panel(
      tag: json['tag'] as String,
      loc: json['loc'] as String,
      type: json['type'] as String? ?? 'PLC HMI',
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
      lastInspectedAt: json['last_inspected_at'] as String?,
      color: json['color'] as String?,
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tag': tag,
      'loc': loc,
      'type': type,
      'latitude': latitude,
      'longitude': longitude,
      'last_inspected_at': lastInspectedAt,
      'color': color,
      'note': note,
    };
  }

  Panel copyWith({
    String? tag,
    String? loc,
    String? type,
    double? latitude,
    double? longitude,
    String? lastInspectedAt,
    String? color,
    String? note,
  }) {
    return Panel(
      tag: tag ?? this.tag,
      loc: loc ?? this.loc,
      type: type ?? this.type,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      lastInspectedAt: lastInspectedAt ?? this.lastInspectedAt,
      color: color ?? this.color,
      note: note ?? this.note,
    );
  }
}

