import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/vehicle.dart';
import 'database.dart';

/// A bike the rider keeps on the device, with or without an account.
@immutable
class LocalBike {
  const LocalBike({
    this.id,
    required this.plate,
    required this.label,
    this.year,
    this.mileageKm = 0,
  });

  final int? id;
  final String plate;
  final String label;
  final int? year;
  final int mileageKm;

  factory LocalBike.fromRow(Map<String, Object?> row) => LocalBike(
    id: row['id'] as int,
    plate: row['plate'] as String,
    label: row['label'] as String,
    year: row['year'] as int?,
    mileageKm: row['mileage_km'] as int,
  );

  Map<String, Object?> toRow() => {
    'plate': normalizePlate(plate),
    'label': label.trim(),
    'year': year,
    'mileage_km': mileageKm,
  };
}

/// A service the rider wrote down: done at home, or at a shop not on Mototeca.
@immutable
class MaintenanceNote {
  const MaintenanceNote({
    this.id,
    required this.bikeId,
    required this.doneOn,
    required this.description,
    this.mileageKm,
    this.costCents,
  });

  final int? id;
  final int bikeId;
  final DateTime doneOn;
  final String description;
  final int? mileageKm;
  final int? costCents;

  factory MaintenanceNote.fromRow(Map<String, Object?> row) => MaintenanceNote(
    id: row['id'] as int,
    bikeId: row['bike_id'] as int,
    doneOn: DateTime.parse(row['done_on'] as String),
    description: row['description'] as String,
    mileageKm: row['mileage_km'] as int?,
    costCents: row['cost_cents'] as int?,
  );

  Map<String, Object?> toRow() => {
    'bike_id': bikeId,
    'done_on': doneOn.toIso8601String(),
    'description': description.trim(),
    'mileage_km': mileageKm,
    'cost_cents': costCents,
  };
}

class DuplicatePlateException implements Exception {
  const DuplicatePlateException(this.plate);

  final String plate;

  @override
  String toString() => 'A moto $plate já está na garagem.';
}

/// The rider's bikes and maintenance notes in SQLite. Signing in does not
/// clear them, so signing out again loses nothing.
class LocalGarage extends ChangeNotifier {
  LocalGarage(this._db);

  final AppDatabase _db;

  var _bikes = <LocalBike>[];
  var _loaded = false;

  List<LocalBike> get bikes => List.unmodifiable(_bikes);
  bool get isEmpty => _bikes.isEmpty;
  int get length => _bikes.length;
  bool get isLoaded => _loaded;

  Future<void> ensureLoaded() async {
    if (!_loaded) await load();
  }

  Future<void> load() async {
    final db = await _db.database;
    final rows = await db.query('bikes', orderBy: 'created_at, id');
    _bikes = rows.map(LocalBike.fromRow).toList();
    _loaded = true;
    notifyListeners();
  }

  Future<void> save(LocalBike bike) async {
    final db = await _db.database;
    try {
      if (bike.id == null) {
        await db.insert('bikes', {
          ...bike.toRow(),
          'created_at': DateTime.now().toIso8601String(),
        });
      } else {
        await db.update(
          'bikes',
          bike.toRow(),
          where: 'id = ?',
          whereArgs: [bike.id],
        );
      }
    } on DatabaseException catch (error) {
      if (!error.isUniqueConstraintError()) rethrow;
      throw DuplicatePlateException(normalizePlate(bike.plate));
    }
    await load();
  }

  /// Deletes the bike and, by cascade, its notes.
  Future<void> remove(int id) async {
    final db = await _db.database;
    await db.delete('bikes', where: 'id = ?', whereArgs: [id]);
    await load();
  }

  Future<List<MaintenanceNote>> notes(int bikeId) async {
    final db = await _db.database;
    final rows = await db.query(
      'maintenance_notes',
      where: 'bike_id = ?',
      whereArgs: [bikeId],
      orderBy: 'done_on DESC, id DESC',
    );
    return rows.map(MaintenanceNote.fromRow).toList();
  }

  /// Saves the note and raises the bike's odometer when the note is ahead of it.
  Future<void> saveNote(MaintenanceNote note) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      if (note.id == null) {
        await txn.insert('maintenance_notes', note.toRow());
      } else {
        await txn.update(
          'maintenance_notes',
          note.toRow(),
          where: 'id = ?',
          whereArgs: [note.id],
        );
      }
      if (note.mileageKm case final km?) {
        await txn.update(
          'bikes',
          {'mileage_km': km},
          where: 'id = ? AND mileage_km < ?',
          whereArgs: [note.bikeId, km],
        );
      }
    });
    await load();
  }

  Future<void> removeNote(int id) async {
    final db = await _db.database;
    await db.delete('maintenance_notes', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }
}
