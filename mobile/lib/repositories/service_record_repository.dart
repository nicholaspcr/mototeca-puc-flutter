import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/service_operation.dart';
import '../models/service_record.dart';
import '../models/vehicle.dart';

/// The history of one plate: the vehicle plus every record, newest first.
class PlateHistory {
  const PlateHistory({required this.vehicle, required this.records});

  final VehicleSummary vehicle;
  final List<ServiceRecord> records;
}

/// What the oficina dashboard needs in one call.
class WorkshopFeed {
  const WorkshopFeed({required this.records, required this.countThisMonth});

  final List<ServiceRecord> records;
  final int countThisMonth;
}

class ServiceRecordRepository {
  const ServiceRecordRepository(this._client);

  final ApiClient _client;

  static const _service = 'mototeca.service.v1.ServiceRecordService';

  Future<ServiceRecord> create({
    required String plate,
    required List<ServiceOperation> operations,
    required int mileageKm,
    String? mechanicName,
    int? costCents,
    String? notes,
    List<Part> parts = const [],
    bool confirmLowerMileage = false,
  }) async {
    final body = await _client.call('$_service/CreateServiceRecord', {
      'plate': normalizePlate(plate),
      'operations': operations.map((o) => o.wire).toList(),
      'mileageKm': mileageKm,
      if (mechanicName != null && mechanicName.trim().isNotEmpty)
        'mechanicName': mechanicName.trim(),
      'costCents': ?costCents,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (parts.isNotEmpty) 'parts': parts.map((p) => p.toJson()).toList(),
      if (confirmLowerMileage) 'confirmLowerMileage': true,
    });
    return ServiceRecord.fromJson(
      body['record'] as Map<String, dynamic>? ?? const {},
    );
  }

  /// Corrects a record the workshop wrote. The original is superseded, never
  /// edited, and its photos and invoice move to the correction.
  Future<ServiceRecord> revise({
    required String recordId,
    required List<ServiceOperation> operations,
    required int mileageKm,
    String? mechanicName,
    int? costCents,
    String? notes,
    List<Part> parts = const [],
  }) async {
    final body = await _client.call('$_service/ReviseServiceRecord', {
      'recordId': recordId,
      'operations': operations.map((o) => o.wire).toList(),
      'mileageKm': mileageKm,
      if (mechanicName != null && mechanicName.trim().isNotEmpty)
        'mechanicName': mechanicName.trim(),
      'costCents': ?costCents,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (parts.isNotEmpty) 'parts': parts.map((p) => p.toJson()).toList(),
    });
    return ServiceRecord.fromJson(
      body['record'] as Map<String, dynamic>? ?? const {},
    );
  }

  /// Returns null when no vehicle is registered under the plate — the empty
  /// state the Portal do Proprietário shows, not an error.
  Future<PlateHistory?> historyByPlate(String plate) async {
    try {
      final body = await _client.call('$_service/ListServiceRecordsByPlate', {
        'plate': normalizePlate(plate),
      });
      return PlateHistory(
        vehicle: VehicleSummary.fromJson(
          body['vehicle'] as Map<String, dynamic>? ?? const {},
        ),
        records: ServiceRecord.listFromJson(body['records'] as List<dynamic>?),
      );
    } on ApiException catch (e) {
      if (e.code == ApiErrorCode.notFound) return null;
      rethrow;
    }
  }

  Future<ServiceRecord> byId(String id) async {
    final body = await _client.call('$_service/GetServiceRecord', {'id': id});
    return ServiceRecord.fromJson(
      body['record'] as Map<String, dynamic>? ?? const {},
    );
  }

  /// Attaches a photo or the invoice to a record the workshop owns. The record
  /// must exist first, which is why this runs after the record is saved.
  Future<Attachment> uploadAttachment({
    required String recordId,
    required List<int> bytes,
    required String filename,
    required String contentType,
    String kind = 'photo',
    String? phase,
  }) async {
    final body = await _client.upload(
      'v1/service-records/$recordId/attachments',
      bytes: bytes,
      filename: filename,
      contentType: contentType,
      fields: {'kind': kind, 'phase': ?phase},
    );
    return Attachment.fromJson(body);
  }

  Future<WorkshopFeed> workshopFeed({int limit = 20}) async {
    final body = await _client.call('$_service/ListWorkshopServiceRecords', {
      'limit': limit,
    });
    return WorkshopFeed(
      records: ServiceRecord.listFromJson(body['records'] as List<dynamic>?),
      countThisMonth: (body['countThisMonth'] as num?)?.toInt() ?? 0,
    );
  }
}
