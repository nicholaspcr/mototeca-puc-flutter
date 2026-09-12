import 'service_record.dart';
import 'vehicle.dart';

class Owner {
  const Owner({required this.id, required this.name, required this.phone});

  final String id;
  final String name;
  final String phone;

  factory Owner.fromJson(Map<String, dynamic> json) => Owner(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
  );
}

/// An owner plus the session token issued with it.
class OwnerSession {
  const OwnerSession({required this.owner, required this.token});

  final Owner owner;
  final String token;

  factory OwnerSession.fromJson(Map<String, dynamic> json) => OwnerSession(
    owner: Owner.fromJson(json['owner'] as Map<String, dynamic>? ?? const {}),
    token: json['token'] as String? ?? '',
  );
}

/// One bike on "Minhas Motos". The backend derives the reminder from the
/// service history; the app doesn't re-implement the rule.
class OwnedVehicle {
  const OwnedVehicle({
    required this.vehicle,
    required this.currentMileageKm,
    required this.serviceCount,
    required this.reminder,
    required this.reminderIsDue,
    this.nextOilChangeKm = 0,
    this.oilChangeIntervalKm = 0,
    this.lastService,
  });

  final VehicleSummary vehicle;
  final int currentMileageKm;
  final int serviceCount;
  final String reminder;
  final bool reminderIsDue;

  /// Both 0 when the bike has no oil change on record.
  final int nextOilChangeKm;
  final int oilChangeIntervalKm;

  final ServiceRecord? lastService;

  bool get hasSchedule => oilChangeIntervalKm > 0 && nextOilChangeKm > 0;

  /// 0..1 through the interval; saturates rather than overflowing the bar.
  double get scheduleProgress {
    if (!hasSchedule) return 0;
    final ridden = oilChangeIntervalKm - (nextOilChangeKm - currentMileageKm);
    return (ridden / oilChangeIntervalKm).clamp(0.0, 1.0);
  }

  /// Negative once overdue.
  int get kmUntilDue => nextOilChangeKm - currentMileageKm;

  String get plate => vehicle.plate;
  String get label => vehicle.label;
  int get year => vehicle.year;

  factory OwnedVehicle.fromJson(Map<String, dynamic> json) {
    final last = json['lastService'] as Map<String, dynamic>?;
    return OwnedVehicle(
      vehicle: VehicleSummary.fromJson(
        json['vehicle'] as Map<String, dynamic>? ?? const {},
      ),
      currentMileageKm: (json['currentMileageKm'] as num?)?.toInt() ?? 0,
      serviceCount: (json['serviceCount'] as num?)?.toInt() ?? 0,
      reminder: json['reminder'] as String? ?? '',
      reminderIsDue: json['reminderIsDue'] as bool? ?? false,
      nextOilChangeKm: (json['nextOilChangeKm'] as num?)?.toInt() ?? 0,
      oilChangeIntervalKm: (json['oilChangeIntervalKm'] as num?)?.toInt() ?? 0,
      lastService: last == null ? null : ServiceRecord.fromJson(last),
    );
  }
}

/// Strips the punctuation people type into a phone field.
String normalizePhone(String raw) => raw.replaceAll(RegExp(r'\D'), '');
