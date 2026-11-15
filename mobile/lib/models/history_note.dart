/// A maintenance note an owner published to a plate's history. No workshop
/// vouches for it, so screens always show it apart from the service records.
class HistoryNote {
  const HistoryNote({
    required this.id,
    required this.doneOn,
    required this.description,
    this.mileageKm,
    this.costCents,
    this.photoUrl,
  });

  final String id;
  final DateTime doneOn;
  final String description;
  final int? mileageKm;
  final int? costCents;
  final String? photoUrl;

  factory HistoryNote.fromJson(Map<String, dynamic> json) => HistoryNote(
    id: json['id'] as String? ?? '',
    // A calendar day; parsing it as local midnight keeps it on that day.
    doneOn:
        DateTime.tryParse(json['doneOn'] as String? ?? '') ?? DateTime.now(),
    description: json['description'] as String? ?? '',
    mileageKm: (json['mileageKm'] as num?)?.toInt(),
    costCents: (json['costCents'] as num?)?.toInt(),
    photoUrl: json['photoUrl'] as String?,
  );

  static List<HistoryNote> listFromJson(List<dynamic>? raw) => (raw ?? const [])
      .map((n) => HistoryNote.fromJson(n as Map<String, dynamic>))
      .toList();
}

/// "2026-10-03", the day as the API takes it.
String formatDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Newest day first. Within a day, by odometer: a note carries a day, not an
/// hour, so it may describe work done before a service published that morning.
int newestFirst((DateTime, int?) a, (DateTime, int?) b) {
  DateTime day(DateTime moment) {
    final local = moment.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  final byDay = day(b.$1).compareTo(day(a.$1));
  if (byDay != 0) return byDay;
  final byKm = (b.$2 ?? 0).compareTo(a.$2 ?? 0);
  return byKm != 0 ? byKm : b.$1.compareTo(a.$1);
}
