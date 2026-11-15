import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/owner.dart';
import '../models/workshop.dart';

/// The signed-in account, kept between launches so the app does not ask for
/// the password every time it opens. The server still checks every token.
class SessionStore {
  SessionStore({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const _key = 'session';

  final DateTime Function() _clock;

  Future<void> saveWorkshop(WorkshopSession session) => _save({
    'kind': 'workshop',
    'token': session.token,
    'workshop': session.workshop.toJson(),
  });

  Future<void> saveOwner(OwnerSession session) => _save({
    'kind': 'owner',
    'token': session.token,
    'owner': session.owner.toJson(),
  });

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  Future<WorkshopSession?> loadWorkshop() async {
    final saved = await _load('workshop');
    return saved == null ? null : WorkshopSession.fromJson(saved);
  }

  Future<OwnerSession?> loadOwner() async {
    final saved = await _load('owner');
    return saved == null ? null : OwnerSession.fromJson(saved);
  }

  Future<void> _save(Map<String, Object?> session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(session));
  }

  Future<Map<String, dynamic>?> _load(String kind) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      final session = jsonDecode(raw) as Map<String, dynamic>;
      if (session['kind'] != kind) return null;
      final expiry = tokenExpiry(session['token'] as String? ?? '');
      if (expiry != null && !expiry.isAfter(_clock())) {
        await clear();
        return null;
      }
      return session;
    } on Object {
      // Unreadable data from an older build: sign in again.
      await clear();
      return null;
    }
  }
}

/// Reads the expiry the API signs into `<kind>:<id>:<unix seconds>`; null for
/// a token in any other shape, which is left for the server to judge.
DateTime? tokenExpiry(String token) {
  try {
    final payload = token.split('.').first;
    final fields = utf8
        .decode(base64Url.decode(base64Url.normalize(payload)))
        .split(':');
    if (fields.length != 3) return null;
    final seconds = int.tryParse(fields[2]);
    return seconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  } on FormatException {
    return null;
  }
}
