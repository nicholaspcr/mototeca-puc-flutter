/// The vehicle fields the public plate lookup returns. Deliberately no chassi
/// and no owner — see ARCHITECTURE.md section 8.
class VehicleSummary {
  const VehicleSummary({
    required this.plate,
    required this.make,
    required this.model,
    required this.year,
  });

  final String plate;
  final String make;
  final String model;
  final int year;

  String get label => '$make $model';
  String get labelWithYear => '$make $model ($year)';

  factory VehicleSummary.fromJson(Map<String, dynamic> json) => VehicleSummary(
    plate: json['plate'] as String? ?? '',
    make: json['make'] as String? ?? '',
    model: json['model'] as String? ?? '',
    year: (json['year'] as num?)?.toInt() ?? 0,
  );
}

/// The full vehicle, returned when a workshop registers or looks one up.
class Vehicle {
  const Vehicle({
    required this.id,
    required this.plate,
    required this.chassi,
    required this.make,
    required this.model,
    required this.year,
  });

  final String id;
  final String plate;
  final String chassi;
  final String make;
  final String model;
  final int year;

  String get label => '$make $model';
  String get labelWithYear => '$make $model ($year)';

  VehicleSummary get summary =>
      VehicleSummary(plate: plate, make: make, model: model, year: year);

  factory Vehicle.fromJson(Map<String, dynamic> json) => Vehicle(
    id: json['id'] as String? ?? '',
    plate: json['plate'] as String? ?? '',
    chassi: json['chassi'] as String? ?? '',
    make: json['make'] as String? ?? '',
    model: json['model'] as String? ?? '',
    year: (json['year'] as num?)?.toInt() ?? 0,
  );
}

/// Strips the separator so 'abc-1d23' and 'ABC1D23' are the same plate, the
/// way the backend normalizes it.
String normalizePlate(String raw) =>
    raw.trim().toUpperCase().replaceAll('-', '').replaceAll(' ', '');
