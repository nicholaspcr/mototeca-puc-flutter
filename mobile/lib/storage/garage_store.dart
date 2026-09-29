import 'package:flutter/foundation.dart';

import '../models/vehicle.dart';
import 'local_store.dart';

/// A bike the rider added before creating an account: only what they can know
/// without the server. History, reminders and ownership arrive with the account.
@immutable
class LocalBike {
  const LocalBike({
    required this.plate,
    required this.label,
    required this.year,
    required this.mileageKm,
    this.note = '',
  });

  final String plate;
  final String label;
  final int year;
  final int mileageKm;

  /// Free text the rider typed: a service done, a part, a price.
  final String note;

  factory LocalBike.fromJson(Map<String, dynamic> json) => LocalBike(
    plate: json['plate'] as String? ?? '',
    label: json['label'] as String? ?? '',
    year: (json['year'] as num?)?.toInt() ?? 0,
    mileageKm: (json['mileageKm'] as num?)?.toInt() ?? 0,
    note: json['note'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'plate': plate,
    'label': label,
    'year': year,
    'mileageKm': mileageKm,
    if (note.isNotEmpty) 'note': note,
  };
}

/// The rider's bikes on this device (design/Main.dc.html). Signing in does not
/// clear it, so signing out again loses nothing.
class LocalGarage extends ChangeNotifier {
  LocalGarage(this._store);

  static const storeKey = 'garage';

  final LocalStore _store;

  var _bikes = <LocalBike>[];
  var _loaded = false;

  List<LocalBike> get bikes => List.unmodifiable(_bikes);
  bool get isEmpty => _bikes.isEmpty;
  int get length => _bikes.length;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final document = await _store.read(storeKey);
    final raw = document?['bikes'] as List<dynamic>? ?? const [];
    _bikes = [
      for (final bike in raw)
        if (bike is Map<String, dynamic>) LocalBike.fromJson(bike),
    ];
    _loaded = true;
    notifyListeners();
  }

  /// Adds the bike, or replaces the one already under that plate.
  Future<void> save(LocalBike bike) async {
    final plate = normalizePlate(bike.plate);
    _bikes = [
      for (final existing in _bikes)
        if (normalizePlate(existing.plate) != plate) existing,
      LocalBike(
        plate: plate,
        label: bike.label,
        year: bike.year,
        mileageKm: bike.mileageKm,
        note: bike.note,
      ),
    ];
    await _persist();
  }

  Future<void> remove(String plate) async {
    final wanted = normalizePlate(plate);
    _bikes = [
      for (final bike in _bikes)
        if (normalizePlate(bike.plate) != wanted) bike,
    ];
    await _persist();
  }

  Future<void> _persist() async {
    await _store.write(storeKey, {
      'bikes': [for (final bike in _bikes) bike.toJson()],
    });
    notifyListeners();
  }
}
