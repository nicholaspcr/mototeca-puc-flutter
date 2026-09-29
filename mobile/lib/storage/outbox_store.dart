import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/service_operation.dart';
import '../models/service_record.dart';
import '../repositories/service_record_repository.dart';
import 'local_store.dart';

/// A service record written in the box and still on the phone: records are
/// always written locally first, published after (design/Outbox.dc.html).
@immutable
class OutboxDraft {
  const OutboxDraft({
    required this.id,
    required this.plate,
    required this.vehicleLabel,
    required this.operations,
    required this.mileageKm,
    required this.savedAt,
    this.mechanicName = '',
    this.costCents,
    this.notes = '',
    this.parts = const [],
    this.photoPaths = const [],
    this.invoicePath,
  });

  final String id;
  final String plate;
  final String vehicleLabel;
  final List<ServiceOperation> operations;
  final int mileageKm;
  final DateTime savedAt;
  final String mechanicName;
  final int? costCents;
  final String notes;
  final List<Part> parts;

  /// Files stay where the camera put them; copying them in would make the
  /// queue as heavy as the photos. A file since deleted is skipped on send.
  final List<String> photoPaths;
  final String? invoicePath;

  int get attachmentCount => photoPaths.length + (invoicePath == null ? 0 : 1);

  String get operationsLabel =>
      operations.map((operation) => operation.label).join(', ');

  factory OutboxDraft.fromJson(Map<String, dynamic> json) => OutboxDraft(
    id: json['id'] as String? ?? '',
    plate: json['plate'] as String? ?? '',
    vehicleLabel: json['vehicleLabel'] as String? ?? '',
    operations: ServiceOperation.listFromWire(
      json['operations'] as List<dynamic>?,
    ),
    mileageKm: (json['mileageKm'] as num?)?.toInt() ?? 0,
    savedAt:
        DateTime.tryParse(json['savedAt'] as String? ?? '') ?? DateTime.now(),
    mechanicName: json['mechanicName'] as String? ?? '',
    costCents: (json['costCents'] as num?)?.toInt(),
    notes: json['notes'] as String? ?? '',
    parts: [
      for (final part in json['parts'] as List<dynamic>? ?? const [])
        if (part is Map<String, dynamic>) Part.fromJson(part),
    ],
    photoPaths: [
      for (final path in json['photoPaths'] as List<dynamic>? ?? const [])
        if (path is String) path,
    ],
    invoicePath: json['invoicePath'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'plate': plate,
    'vehicleLabel': vehicleLabel,
    'operations': [for (final operation in operations) operation.wire],
    'mileageKm': mileageKm,
    'savedAt': savedAt.toIso8601String(),
    if (mechanicName.isNotEmpty) 'mechanicName': mechanicName,
    'costCents': ?costCents,
    if (notes.isNotEmpty) 'notes': notes,
    if (parts.isNotEmpty) 'parts': [for (final part in parts) part.toJson()],
    if (photoPaths.isNotEmpty) 'photoPaths': photoPaths,
    'invoicePath': ?invoicePath,
  };
}

/// What one [Outbox.flush] did, for the message the screen shows afterwards.
class FlushResult {
  const FlushResult({required this.sent, required this.failed});

  final int sent;
  final int failed;

  bool get isEmpty => sent == 0 && failed == 0;
}

/// Records waiting to be published. Nothing leaves the device before sign-in:
/// a record in the public history is signed by the CNPJ that wrote it.
class Outbox extends ChangeNotifier {
  Outbox(this._store);

  static const storeKey = 'outbox';

  final LocalStore _store;

  var _drafts = <OutboxDraft>[];
  var _loaded = false;

  /// Oldest first, which is the order they are sent in.
  List<OutboxDraft> get drafts => List.unmodifiable(_drafts);
  int get length => _drafts.length;
  bool get isEmpty => _drafts.isEmpty;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final document = await _store.read(storeKey);
    final raw = document?['drafts'] as List<dynamic>? ?? const [];
    _drafts = [
      for (final draft in raw)
        if (draft is Map<String, dynamic>) OutboxDraft.fromJson(draft),
    ]..sort((a, b) => a.savedAt.compareTo(b.savedAt));
    _loaded = true;
    notifyListeners();
  }

  Future<void> add(OutboxDraft draft) async {
    _drafts = [..._drafts, draft];
    await _persist();
  }

  Future<void> remove(String id) async {
    _drafts = [
      for (final draft in _drafts)
        if (draft.id != id) draft,
    ];
    await _persist();
  }

  /// Publishes oldest first, dropping what lands. A refused draft stays queued.
  Future<FlushResult> flush(ServiceRecordRepository records) async {
    var sent = 0;
    var failed = 0;
    for (final draft in drafts) {
      try {
        final record = await records.create(
          plate: draft.plate,
          operations: draft.operations,
          mileageKm: draft.mileageKm,
          mechanicName: draft.mechanicName,
          costCents: draft.costCents,
          notes: draft.notes,
          parts: draft.parts,
          // Already confirmed when typed; the bike is long gone by now.
          confirmLowerMileage: true,
        );
        await _uploadAttachments(records, record.id, draft);
        await remove(draft.id);
        sent++;
      } on Object {
        failed++;
      }
    }
    return FlushResult(sent: sent, failed: failed);
  }

  Future<void> _uploadAttachments(
    ServiceRecordRepository records,
    String recordId,
    OutboxDraft draft,
  ) async {
    if (kIsWeb) return;
    for (final path in draft.photoPaths) {
      await _upload(records, recordId, path, kind: 'photo', phase: 'after');
    }
    final invoice = draft.invoicePath;
    if (invoice != null) {
      await _upload(records, recordId, invoice, kind: 'invoice');
    }
  }

  /// A photo gone from disk is skipped; the record is already saved.
  Future<void> _upload(
    ServiceRecordRepository records,
    String recordId,
    String path, {
    required String kind,
    String? phase,
  }) async {
    try {
      final file = File(path);
      if (!await file.exists()) return;
      await records.uploadAttachment(
        recordId: recordId,
        bytes: await file.readAsBytes(),
        filename: path.split('/').last,
        contentType: 'image/jpeg',
        kind: kind,
        phase: phase,
      );
    } on Object {
      // A lost photo does not put a saved record back in the queue.
    }
  }

  Future<void> _persist() async {
    await _store.write(storeKey, {
      'drafts': [for (final draft in _drafts) draft.toJson()],
    });
    notifyListeners();
  }
}
