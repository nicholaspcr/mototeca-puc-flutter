import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/service_operation.dart';
import '../models/service_record.dart';
import '../repositories/service_record_repository.dart';
import 'database.dart';

/// A photo or invoice held with its draft, so it survives until the upload.
@immutable
class OutboxAttachment {
  const OutboxAttachment({
    required this.kind,
    this.phase,
    required this.filename,
    required this.contentType,
    required this.bytes,
  });

  final String kind;
  final String? phase;
  final String filename;
  final String contentType;
  final Uint8List bytes;

  factory OutboxAttachment.fromRow(Map<String, Object?> row) =>
      OutboxAttachment(
        kind: row['kind'] as String,
        phase: row['phase'] as String?,
        filename: row['filename'] as String,
        contentType: row['content_type'] as String,
        bytes: row['bytes'] as Uint8List,
      );

  Map<String, Object?> toRow(int draftId) => {
    'draft_id': draftId,
    'kind': kind,
    'phase': phase,
    'filename': filename,
    'content_type': contentType,
    'bytes': bytes,
  };
}

/// A service record saved on the device and not yet published.
@immutable
class OutboxDraft {
  const OutboxDraft({
    this.id,
    required this.plate,
    required this.vehicleLabel,
    required this.operations,
    required this.mileageKm,
    required this.savedAt,
    this.mechanicName = '',
    this.costCents,
    this.notes = '',
    this.parts = const [],
    this.attachments = const [],
  });

  final int? id;
  final String plate;
  final String vehicleLabel;
  final List<ServiceOperation> operations;
  final int mileageKm;
  final DateTime savedAt;
  final String mechanicName;
  final int? costCents;
  final String notes;
  final List<Part> parts;
  final List<OutboxAttachment> attachments;

  int get attachmentCount => attachments.length;

  String get operationsLabel =>
      operations.map((operation) => operation.label).join(', ');

  Map<String, Object?> toRow() => {
    'plate': plate,
    'vehicle_label': vehicleLabel,
    'mileage_km': mileageKm,
    'mechanic_name': mechanicName,
    'cost_cents': costCents,
    'notes': notes,
    'saved_at': savedAt.toIso8601String(),
  };
}

/// "1 registro", "3 registros".
String recordCount(int count) =>
    '$count ${count == 1 ? 'registro' : 'registros'}';

class FlushResult {
  const FlushResult({required this.sent, required this.failed});

  final int sent;
  final int failed;

  bool get isEmpty => sent == 0 && failed == 0;
}

/// Records waiting to be published, in SQLite. Nothing leaves the device
/// before sign-in: a public record is signed by the CNPJ that wrote it.
class Outbox extends ChangeNotifier {
  Outbox(this._db);

  final AppDatabase _db;

  var _drafts = <OutboxDraft>[];
  var _loaded = false;

  /// Oldest first, which is the order they are sent in.
  List<OutboxDraft> get drafts => List.unmodifiable(_drafts);
  int get length => _drafts.length;
  bool get isEmpty => _drafts.isEmpty;
  bool get isLoaded => _loaded;

  Future<void> ensureLoaded() async {
    if (!_loaded) await load();
  }

  Future<void> load() async {
    final db = await _db.database;
    final rows = await db.query('outbox_drafts', orderBy: 'saved_at, id');
    _drafts = [for (final row in rows) await _readDraft(db, row)];
    _loaded = true;
    notifyListeners();
  }

  Future<OutboxDraft> _readDraft(
    DatabaseExecutor db,
    Map<String, Object?> row,
  ) async {
    final id = row['id'] as int;
    final operations = await db.query(
      'outbox_operations',
      where: 'draft_id = ?',
      whereArgs: [id],
      orderBy: 'rowid',
    );
    final parts = await db.query(
      'outbox_parts',
      where: 'draft_id = ?',
      whereArgs: [id],
      orderBy: 'id',
    );
    final attachments = await db.query(
      'outbox_attachments',
      where: 'draft_id = ?',
      whereArgs: [id],
      orderBy: 'id',
    );
    return OutboxDraft(
      id: id,
      plate: row['plate'] as String,
      vehicleLabel: row['vehicle_label'] as String,
      mileageKm: row['mileage_km'] as int,
      mechanicName: row['mechanic_name'] as String,
      costCents: row['cost_cents'] as int?,
      notes: row['notes'] as String,
      savedAt: DateTime.parse(row['saved_at'] as String),
      operations: ServiceOperation.listFromWire([
        for (final operation in operations) operation['operation'],
      ]),
      parts: [
        for (final part in parts)
          Part(
            name: part['name'] as String,
            quantity: part['quantity'] as int,
            costCents: part['cost_cents'] as int?,
          ),
      ],
      attachments: attachments.map(OutboxAttachment.fromRow).toList(),
    );
  }

  /// Writes the draft and its children in one transaction.
  Future<void> add(OutboxDraft draft) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final id = await txn.insert('outbox_drafts', draft.toRow());
      for (final operation in draft.operations) {
        await txn.insert('outbox_operations', {
          'draft_id': id,
          'operation': operation.wire,
        });
      }
      for (final part in draft.parts) {
        await txn.insert('outbox_parts', {
          'draft_id': id,
          'name': part.name,
          'quantity': part.quantity,
          'cost_cents': part.costCents,
        });
      }
      for (final attachment in draft.attachments) {
        await txn.insert('outbox_attachments', attachment.toRow(id));
      }
    });
    await load();
  }

  /// Deletes the draft; its operations, parts and files go by cascade.
  Future<void> remove(int id) async {
    final db = await _db.database;
    await db.delete('outbox_drafts', where: 'id = ?', whereArgs: [id]);
    await load();
  }

  /// Publishes oldest first and deletes what lands. A refused draft stays.
  Future<FlushResult> flush(ServiceRecordRepository records) async {
    await ensureLoaded();
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
        await remove(draft.id!);
        sent++;
      } on Object {
        failed++;
      }
    }
    return FlushResult(sent: sent, failed: failed);
  }

  /// A failed upload does not put a published record back in the queue.
  Future<void> _uploadAttachments(
    ServiceRecordRepository records,
    String recordId,
    OutboxDraft draft,
  ) async {
    for (final attachment in draft.attachments) {
      try {
        await records.uploadAttachment(
          recordId: recordId,
          bytes: attachment.bytes,
          filename: attachment.filename,
          contentType: attachment.contentType,
          kind: attachment.kind,
          phase: attachment.phase,
        );
      } on Object {
        continue;
      }
    }
  }
}
