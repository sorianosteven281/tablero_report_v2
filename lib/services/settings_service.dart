import 'database_service.dart';

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  final DatabaseService _db = DatabaseService();

  static const String keyResponsible = 'settings_responsible_name';
  static const String keyCrew = 'settings_crew_name';

  static const String defaultResponsible = 'Pon tu nombre';
  static const String defaultCrew = 'Guardia A - Mantenimiento Eléctrico';

  Future<String> getResponsibleName() async {
    return await _db.getSetting(keyResponsible, defaultResponsible);
  }

  Future<void> setResponsibleName(String name) async {
    await _db.setSetting(keyResponsible, name.trim().isEmpty ? defaultResponsible : name.trim());
  }

  Future<String> getCrewName() async {
    return await _db.getSetting(keyCrew, defaultCrew);
  }

  Future<void> setCrewName(String crew) async {
    await _db.setSetting(keyCrew, crew.trim().isEmpty ? defaultCrew : crew.trim());
  }
}
