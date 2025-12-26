import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalDbService {
  static Database? _db;

  static Future<Database> _ensureDb() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'twc_location.db');

    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE location_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            driver_id TEXT,
            device_id TEXT,
            timestamp TEXT,
            latitude REAL,
            longitude REAL,
            accuracy REAL,
            battery_level REAL,
            status TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // v1 → v2: add status column, default 'pending'
          await db.execute(
            "ALTER TABLE location_records ADD COLUMN status TEXT DEFAULT 'pending'",
          );
        }
      },
    );
    return _db!;
  }

  /// Optional explicit init
  static Future<void> init() async {
    await _ensureDb();
  }

  /// Insert one location record.
  /// [json] is usually LocationRecord.toJson().
  /// We always store as 'pending' by default.
  static Future<int> insertRecord(
      Map<String, dynamic> json, {
        String status = 'pending',
      }) async {
    final db = await _ensureDb();

    return await db.insert('location_records', {
      'driver_id': json['driver_id'],
      'device_id': json['device_id'],
      'timestamp': json['timestamp'],
      'latitude': json['latitude'],
      'longitude': json['longitude'],
      'accuracy': json['accuracy'],
      'battery_level': json['battery_level'],
      'status': status,
    });
  }

  /// All pending (unsent) records, oldest first.
  static Future<List<Map<String, dynamic>>> getPendingRecords() async {
    final db = await _ensureDb();
    return await db.query(
      'location_records',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'timestamp ASC',
    );
  }

  /// Mark given [ids] as 'sent'.
  static Future<void> markRecordsSent(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _ensureDb();
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.update(
      'location_records',
      {'status': 'sent'},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  /// All records (pending + sent) for UI in Settings.
  static Future<List<Map<String, dynamic>>> getAllRecords() async {
    final db = await _ensureDb();
    return await db.query(
      'location_records',
      orderBy: 'timestamp DESC',
    );
  }

  /// Not used in normal app flow — only for debug / tools.
  static Future<void> clearAll() async {
    final db = await _ensureDb();
    await db.delete('location_records');
  }

  /// Optional cleanup helper (not called automatically).
  static Future<int> deleteOldRecords({int days = 2}) async {
    final db = await _ensureDb();
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(Duration(days: days))
        .toIso8601String();

    final count = await db.delete(
      'location_records',
      where: 'timestamp < ?',
      whereArgs: [cutoff],
    );

    debugPrint(
      "🧹 Cleaned up $count old location records (older than $days days)",
    );
    return count;
  }

  static Future<Map<String, dynamic>?> getLatestRecord() async {
    final db = await _ensureDb();
    final rows = await db.query(
      'location_records',
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }
}