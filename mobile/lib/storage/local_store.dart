import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Storage for what an app keeps before there is an account: both homes work
/// with no session, so that data must survive a restart without the server.
abstract class LocalStore {
  Future<Map<String, dynamic>?> read(String key);
  Future<void> write(String key, Map<String, dynamic> value);
  Future<void> remove(String key);
}

/// The store the app runs with: files on a phone, memory on the web.
LocalStore createLocalStore() =>
    kIsWeb ? MemoryLocalStore() : FileLocalStore();

/// Used by tests and by the web build, which has no app directory.
class MemoryLocalStore implements LocalStore {
  final _documents = <String, Map<String, dynamic>>{};

  @override
  Future<Map<String, dynamic>?> read(String key) async => _documents[key];

  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    _documents[key] = value;
  }

  @override
  Future<void> remove(String key) async => _documents.remove(key);
}

/// One JSON file per key under the app's documents directory. Anything
/// unreadable degrades to memory: losing a draft beats refusing to open.
class FileLocalStore implements LocalStore {
  final _fallback = MemoryLocalStore();
  Future<Directory?>? _directory;

  Future<Directory?> _resolveDirectory() async {
    try {
      return await getApplicationDocumentsDirectory();
    } on Object {
      return null;
    }
  }

  Future<File?> _file(String key) async {
    final directory = await (_directory ??= _resolveDirectory());
    if (directory == null) return null;
    return File('${directory.path}/mototeca_$key.json');
  }

  @override
  Future<Map<String, dynamic>?> read(String key) async {
    final file = await _file(key);
    if (file == null) return _fallback.read(key);
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    final file = await _file(key);
    if (file == null) return _fallback.write(key, value);
    try {
      await file.writeAsString(jsonEncode(value));
    } on Object {
      await _fallback.write(key, value);
    }
  }

  @override
  Future<void> remove(String key) async {
    final file = await _file(key);
    if (file == null) return _fallback.remove(key);
    try {
      if (await file.exists()) await file.delete();
    } on Object {
      // Nothing to do: the next write overwrites it anyway.
    }
  }
}
