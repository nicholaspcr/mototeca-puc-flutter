import 'dart:math';

import 'package:sqflite/sqflite.dart';

import 'database_factory_io.dart'
    if (dart.library.js_interop) 'database_factory_web.dart';

/// The SQLite database holding what the apps keep on the device.
class AppDatabase {
  AppDatabase({DatabaseFactory? factory, this.path = 'mototeca.db'})
    : _factory = factory ?? platformDatabaseFactory();

  static const version = 2;

  final DatabaseFactory _factory;
  final String path;
  Future<Database>? _database;

  Future<Database> get database => _database ??= _open();

  Future<Database> _open() => _factory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: version,
      // Tests open a fresh in-memory database each time; files are shared.
      singleInstance: path != inMemoryDatabasePath,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        for (final statement in schema) {
          await db.execute(statement);
        }
        await _migrate(db, from: 1);
      },
      onUpgrade: (db, from, _) => _migrate(db, from: from),
    ),
  );

  Future<void> close() async => (await _database)?.close();
}

/// Version 2 lets a note be published: the id the device gives it, the id the
/// server answered with, and its one photo.
Future<void> _migrate(Database db, {required int from}) async {
  if (from < 2) {
    for (final column in [
      'client_id TEXT',
      'server_id TEXT',
      'photo BLOB',
      'photo_type TEXT',
      'photo_sent INTEGER NOT NULL DEFAULT 0',
    ]) {
      await db.execute('ALTER TABLE maintenance_notes ADD COLUMN $column');
    }
    for (final row in await db.query('maintenance_notes', columns: ['id'])) {
      await db.update(
        'maintenance_notes',
        {'client_id': newClientId()},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }
}

/// A random UUID (version 4), the form the API expects for a client id.
String newClientId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

const schema = [
  '''
  CREATE TABLE bikes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    plate TEXT NOT NULL UNIQUE,
    label TEXT NOT NULL,
    year INTEGER,
    mileage_km INTEGER NOT NULL DEFAULT 0 CHECK (mileage_km >= 0),
    created_at TEXT NOT NULL
  )''',
  '''
  CREATE TABLE maintenance_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    bike_id INTEGER NOT NULL REFERENCES bikes (id) ON DELETE CASCADE,
    done_on TEXT NOT NULL,
    mileage_km INTEGER CHECK (mileage_km >= 0),
    description TEXT NOT NULL,
    cost_cents INTEGER CHECK (cost_cents >= 0)
  )''',
  'CREATE INDEX maintenance_notes_bike ON maintenance_notes (bike_id, done_on)',
  '''
  CREATE TABLE outbox_drafts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    plate TEXT NOT NULL,
    vehicle_label TEXT NOT NULL,
    mileage_km INTEGER NOT NULL CHECK (mileage_km >= 0),
    mechanic_name TEXT NOT NULL DEFAULT '',
    cost_cents INTEGER CHECK (cost_cents >= 0),
    notes TEXT NOT NULL DEFAULT '',
    saved_at TEXT NOT NULL
  )''',
  '''
  CREATE TABLE outbox_operations (
    draft_id INTEGER NOT NULL REFERENCES outbox_drafts (id) ON DELETE CASCADE,
    operation TEXT NOT NULL,
    PRIMARY KEY (draft_id, operation)
  )''',
  '''
  CREATE TABLE outbox_parts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    draft_id INTEGER NOT NULL REFERENCES outbox_drafts (id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    cost_cents INTEGER CHECK (cost_cents >= 0)
  )''',
  '''
  CREATE TABLE outbox_attachments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    draft_id INTEGER NOT NULL REFERENCES outbox_drafts (id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('photo', 'invoice')),
    phase TEXT CHECK (phase IN ('before', 'after')),
    filename TEXT NOT NULL,
    content_type TEXT NOT NULL,
    bytes BLOB NOT NULL
  )''',
];
