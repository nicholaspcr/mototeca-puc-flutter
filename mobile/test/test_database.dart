import 'package:mototeca/storage/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A fresh in-memory SQLite per call. The no-isolate factory keeps queries
/// synchronous, so they finish inside widget tests' fake async zone.
AppDatabase testDatabase() {
  sqfliteFfiInit();
  return AppDatabase(
    factory: databaseFactoryFfiNoIsolate,
    path: inMemoryDatabasePath,
  );
}
