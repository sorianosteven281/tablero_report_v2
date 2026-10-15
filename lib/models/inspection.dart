class Inspection {
  final int? id;
  final String panelTag;
  final String panelLoc;
  final String panelType;
  final String date;
  final List<String> photosBefore;
  final List<String> photosObs;
  final List<String> photosAfter;
  final String observations;
  final String finalStatus;
  final double? latitude;
  final double? longitude;
  final String responsible;
  final String crew;

  Inspection({
    this.id,
    required this.panelTag,
    required this.panelLoc,
    required this.panelType,
    required this.date,
    required this.photosBefore,
    required this.photosObs,
    required this.photosAfter,
    required this.observations,
    required this.finalStatus,
    this.latitude,
    this.longitude,
    required this.responsible,
    required this.crew,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'panel_tag': panelTag,
      'panel_loc': panelLoc,
      'panel_type': panelType,
      'date': date,
      'photos_before': photosBefore.join(','),
      'photos_obs': photosObs.join(','),
      'photos_after': photosAfter.join(','),
      'observations': observations,
      'status': finalStatus,
      'final_status': finalStatus,
      'latitude': latitude,
      'longitude': longitude,
      'responsible': responsible,
      'crew': crew,
    };
  }

  factory Inspection.fromMap(Map<String, dynamic> map) {
    return Inspection(
      id: map['id'] as int?,
      panelTag: map['panel_tag'] as String,
      panelLoc: map['panel_loc'] as String,
      panelType: map['panel_type'] as String? ?? 'PLC HMI',
      date: map['date'] as String,
      photosBefore: (map['photos_before'] as String?)?.split(',').where((s) => s.isNotEmpty).toList() ?? [],
      photosObs: (map['photos_obs'] as String?)?.split(',').where((s) => s.isNotEmpty).toList() ?? [],
      photosAfter: (map['photos_after'] as String?)?.split(',').where((s) => s.isNotEmpty).toList() ?? [],
      observations: map['observations'] as String? ?? '',
      finalStatus: map['final_status'] as String? ?? map['status'] as String? ?? 'OPERATIVO',
      latitude: map['latitude'] != null ? (map['latitude'] as num).toDouble() : null,
      longitude: map['longitude'] != null ? (map['longitude'] as num).toDouble() : null,
      responsible: map['responsible'] as String? ?? 'Técnico',
      crew: map['crew'] as String? ?? 'Guardia A - Mantenimiento Eléctrico',
    );
  }
}
