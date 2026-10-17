import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/panel.dart';
import '../models/inspection.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'tableros_mantenimiento.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE panels (
            tag TEXT PRIMARY KEY,
            loc TEXT NOT NULL,
            type TEXT NOT NULL,
            latitude REAL,
            longitude REAL,
            last_inspected_at TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE inspections (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            panel_tag TEXT NOT NULL,
            panel_loc TEXT NOT NULL,
            panel_type TEXT NOT NULL,
            date TEXT NOT NULL,
            photos_before TEXT,
            photos_obs TEXT,
            photos_after TEXT,
            observations TEXT,
            final_status TEXT,
            latitude REAL,
            longitude REAL,
            responsible TEXT,
            crew TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE drafts (
            panel_tag TEXT PRIMARY KEY,
            panel_loc TEXT NOT NULL,
            panel_type TEXT NOT NULL,
            crew TEXT,
            responsible TEXT,
            photos_before TEXT,
            photos_obs TEXT,
            photos_after TEXT,
            observations TEXT,
            final_status TEXT,
            updated_at TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');

        await _seedPanels(db);
      },
      onOpen: (db) async {
        // Creación preventiva de tabla settings y migración
        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS settings (
              key TEXT PRIMARY KEY,
              value TEXT
            )
          ''');

          final columns = await db.rawQuery('PRAGMA table_info(inspections)');
          final names = columns.map((c) => c['name'] as String).toSet();

          if (!names.contains('final_status')) {
            await db.execute('ALTER TABLE inspections ADD COLUMN final_status TEXT');
            if (names.contains('status')) {
              await db.execute('UPDATE inspections SET final_status = status WHERE final_status IS NULL');
            }
          }
          if (!names.contains('responsible')) {
            await db.execute('ALTER TABLE inspections ADD COLUMN responsible TEXT');
          }
          if (!names.contains('crew')) {
            await db.execute('ALTER TABLE inspections ADD COLUMN crew TEXT');
          }
        } catch (_) {}
      },
    );
  }

  Future<void> _seedPanels(Database db) async {
    try {
      final jsonString = await rootBundle.loadString('assets/data/panels.json');
      final List<dynamic> list = json.decode(jsonString);
      final batch = db.batch();

      for (var item in list) {
        batch.insert('panels', {
          'tag': item['tag'],
          'loc': item['loc'],
          'type': item['type'] ?? 'PLC HMI',
          'latitude': item['latitude'] != null ? (item['latitude'] as num).toDouble() : null,
          'longitude': item['longitude'] != null ? (item['longitude'] as num).toDouble() : null,
          'last_inspected_at': null,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    } catch (_) {}
  }

  Future<List<Panel>> getAllPanels({String? query}) async {
    final db = await database;
    List<Map<String, dynamic>> maps;

    if (query != null && query.trim().isNotEmpty) {
      final q = '%${query.trim()}%';
      maps = await db.query(
        'panels',
        where: 'tag LIKE ? OR loc LIKE ?',
        whereArgs: [q, q],
        orderBy: 'tag ASC',
      );
    } else {
      maps = await db.query('panels', orderBy: 'tag ASC');
    }

    return maps.map((m) => Panel.fromJson(m)).toList();
  }

  Future<void> updatePanelInspection(String tag, double? lat, double? lon) async {
    final db = await database;
    await db.update(
      'panels',
      {
        'latitude': lat,
        'longitude': lon,
        'last_inspected_at': DateTime.now().toIso8601String(),
      },
      where: 'tag = ?',
      whereArgs: [tag],
    );
  }

  Future<int> insertInspection(Inspection inspection) async {
    final db = await database;
    final cols = await db.rawQuery('PRAGMA table_info(inspections)');
    final colNames = cols.map((c) => c['name'] as String).toSet();

    final data = inspection.toMap();
    final validData = <String, dynamic>{};
    for (var entry in data.entries) {
      if (colNames.contains(entry.key)) {
        validData[entry.key] = entry.value;
      }
    }

    final id = await db.insert('inspections', validData);
    await updatePanelInspection(inspection.panelTag, inspection.latitude, inspection.longitude);
    await deleteDraft(inspection.panelTag);
    return id;
  }

  Future<List<Inspection>> getAllInspections() async {
    final db = await database;
    final maps = await db.query('inspections', orderBy: 'id DESC');
    return maps.map((m) => Inspection.fromMap(m)).toList();
  }

  Future<void> insertPanel(Panel panel) async {
    final db = await database;
    await db.insert(
      'panels',
      panel.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updateInspection(Inspection inspection) async {
    final db = await database;
    final data = inspection.toMap();
    return await db.update(
      'inspections',
      data,
      where: 'id = ?',
      whereArgs: [inspection.id],
    );
  }

  Future<void> saveDraft(String panelTag, Map<String, dynamic> draftData) async {
    final db = await database;
    try {
      await db.insert(
        'drafts',
        {
          'panel_tag': panelTag,
          'panel_loc': draftData['panel_loc'] ?? '',
          'panel_type': draftData['panel_type'] ?? '',
          'crew': draftData['crew'] ?? '',
          'responsible': draftData['responsible'] ?? '',
          'photos_before': draftData['photos_before'] ?? '[]',
          'photos_obs': draftData['photos_obs'] ?? '[]',
          'photos_after': draftData['photos_after'] ?? '[]',
          'observations': draftData['observations'] ?? '',
          'final_status': draftData['final_status'] ?? 'OPERATIVO',
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> getDraft(String panelTag) async {
    final db = await database;
    try {
      final res = await db.query('drafts', where: 'panel_tag = ?', whereArgs: [panelTag]);
      if (res.isNotEmpty) {
        return res.first;
      }
    } catch (_) {}
    return null;
  }

  Future<void> deleteDraft(String panelTag) async {
    final db = await database;
    await db.delete('drafts', where: 'panel_tag = ?', whereArgs: [panelTag]);
  }

  Future<String> getSetting(String key, String defaultValue) async {
    final db = await database;
    try {
      final res = await db.query('settings', where: 'key = ?', whereArgs: [key]);
      if (res.isNotEmpty && res.first['value'] != null) {
        return res.first['value'] as String;
      }
    } catch (_) {}
    return defaultValue;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    try {
      await db.insert(
        'settings',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }
}
