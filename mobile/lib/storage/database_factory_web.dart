import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Runs SQLite as WebAssembly; `web/sqlite3.wasm` and `web/sqflite_sw.js` come
/// from `dart run sqflite_common_ffi_web:setup`.
DatabaseFactory platformDatabaseFactory() => databaseFactoryFfiWeb;
