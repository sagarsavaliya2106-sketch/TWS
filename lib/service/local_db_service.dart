import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalDbService {
  static Database? _db;

  /// Initialize database
  static Future<void> init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'twc_location.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE location_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            employee_id TEXT,
            device_id TEXT,
            timestamp TEXT,
            latitude REAL,
            longitude REAL,
            accuracy REAL,
            battery_level REAL
          )
        ''');
      },
    );
  }

  /// Insert one record
  static Future<void> insertRecord(Map<String, dynamic> json) async {
    await _db?.insert('location_records', json);
  }

  /// Fetch all pending records
  static Future<List<Map<String, dynamic>>> getAllRecords() async {
    return await _db?.query('location_records') ?? [];
  }

  /// Delete all
  static Future<void> clearAll() async {
    await _db?.delete('location_records');
  }

  /// Delete older than 2 days
  static Future<void> deleteOldRecords() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 2));
    await _db?.delete(
      'location_records',
      where: 'timestamp < ?',
      whereArgs: [cutoff.toIso8601String()],
    );
  }
}
