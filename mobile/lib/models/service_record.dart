import 'service_operation.dart';
import 'vehicle.dart';

/// Money crosses the wire as integer cents and is only turned into a string
/// for display — never parsed into a double.
String formatCents(int cents) {
  final reais = cents ~/ 100;
  final centavos = (cents % 100).toString().padLeft(2, '0');
  return 'R\$ $reais,$centavos';
}

/// dd/mm/yyyy in the device's time zone.
String formatDate(DateTime moment) {
  final local = moment.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month/${local.year}';
}

/// Parses what a mechanic types into a money field ("245", "245,50",
/// "R$ 1.245,50") into integer cents.
///
/// Returns null for blank input and throws [FormatException] for something
/// that isn't a number, so the caller can tell "left empty" from "typed
/// nonsense". Deliberately integer-only: parsing money as a double loses
/// centavos.
int? parseCents(String raw) {
  final cleaned = raw
      .trim()
      .replaceAll(RegExp(r'[R$\s.]'), '')
      .replaceAll(',', '.');
  if (cleaned.isEmpty) return null;

  final parts = cleaned.split('.');
  if (parts.length > 2) throw const FormatException('valor inválido');

  final reais = int.parse(parts[0].isEmpty ? '0' : parts[0]);
  if (parts.length == 1) return reais * 100;

  final centavos = int.parse(parts[1].padRight(2, '0').substring(0, 2));
  return reais * 100 + centavos;
}

class Part {
  const Part({required this.name, required this.quantity, this.costCents});

  final String name;
  final int quantity;
  final int? costCents;

  factory Part.fromJson(Map<String, dynamic> json) => Part(
    name: json['name'] as String? ?? '',
    quantity: (json['quantity'] as num?)?.toInt() ?? 1,
    costCents: (json['costCents'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'quantity': quantity,
    if (costCents != null) 'costCents': costCents,
  };
}

/// A photo or the invoice attached to a record.
class Attachment {
  const Attachment({
    required this.id,
    required this.url,
    required this.kind,
    this.phase,
  });

  final String id;
  final String url;
  final String kind;

  /// 'PHOTO_PHASE_BEFORE' / 'PHOTO_PHASE_AFTER'; null on an invoice.
  final String? phase;

  bool get isInvoice => kind == 'invoice';

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
    id: json['id'] as String? ?? '',
    url: json['url'] as String? ?? '',
    kind: json['kind'] as String? ?? 'photo',
    phase: json['phase'] as String?,
  );
}

/// One immutable entry in a bike's history.
class ServiceRecord {
  const ServiceRecord({
    required this.id,
    required this.vehicle,
    required this.workshopName,
    required this.operations,
    required this.mileageKm,
    required this.createdAt,
    this.mechanicName,
    this.costCents,
    this.notes,
    this.parts = const [],
    this.attachments = const [],
  });

  final String id;
  final VehicleSummary vehicle;
  final String workshopName;
  final String? mechanicName;
  final List<ServiceOperation> operations;
  final int mileageKm;
  final int? costCents;
  final String? notes;
  final List<Part> parts;
  final List<Attachment> attachments;
  final DateTime createdAt;

  /// "Troca de óleo e filtro, Pneus" — the one-line summary on list rows.
  String get operationsLabel => operations.map((o) => o.label).join(', ');

  String get formattedDate => formatDate(createdAt);

  String get formattedCost => costCents == null ? '—' : formatCents(costCents!);

  factory ServiceRecord.fromJson(Map<String, dynamic> json) => ServiceRecord(
    id: json['id'] as String? ?? '',
    vehicle: VehicleSummary.fromJson(
      json['vehicle'] as Map<String, dynamic>? ?? const {},
    ),
    workshopName: json['workshopName'] as String? ?? '',
    mechanicName: json['mechanicName'] as String?,
    operations: ServiceOperation.listFromWire(
      json['operations'] as List<dynamic>?,
    ),
    mileageKm: (json['mileageKm'] as num?)?.toInt() ?? 0,
    costCents: (json['costCents'] as num?)?.toInt(),
    notes: json['notes'] as String?,
    parts: (json['parts'] as List<dynamic>? ?? const [])
        .map((p) => Part.fromJson(p as Map<String, dynamic>))
        .toList(),
    attachments: (json['attachments'] as List<dynamic>? ?? const [])
        .map((a) => Attachment.fromJson(a as Map<String, dynamic>))
        .toList(),
    // The server sends RFC 3339 UTC; a malformed value falls back to now
    // rather than taking the whole history down.
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );

  static List<ServiceRecord> listFromJson(List<dynamic>? raw) =>
      (raw ?? const [])
          .map((r) => ServiceRecord.fromJson(r as Map<String, dynamic>))
          .toList();
}
