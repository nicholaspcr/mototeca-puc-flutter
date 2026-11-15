import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/history_note.dart';
import '../models/owner.dart';
import '../models/vehicle.dart';

class OwnerRepository {
  const OwnerRepository(this._client);

  final ApiClient _client;

  static const _service = 'mototeca.owner.v1.OwnerService';

  Future<OwnerSession> createOwner({
    required String name,
    required String phone,
    required String password,
  }) async {
    final body = await _client.call('$_service/CreateOwner', {
      'name': name.trim(),
      'phone': normalizePhone(phone),
      'password': password,
    });
    return OwnerSession.fromJson(body);
  }

  Future<OwnerSession> login({
    required String phone,
    required String password,
  }) async {
    final body = await _client.call('$_service/Login', {
      'phone': normalizePhone(phone),
      'password': password,
    });
    return OwnerSession.fromJson(body);
  }

  Future<List<OwnedVehicle>> myVehicles() async {
    final body = await _client.call('$_service/ListMyVehicles', {});
    return (body['vehicles'] as List<dynamic>? ?? const [])
        .map((v) => OwnedVehicle.fromJson(v as Map<String, dynamic>))
        .toList();
  }

  /// Unlinks a sold bike so its buyer can claim it. The history stays with
  /// the plate.
  Future<void> releaseVehicle(String plate) async {
    await _client.call('$_service/ReleaseVehicle', {
      'plate': normalizePlate(plate),
    });
  }

  /// Links an already-registered bike to the signed-in owner, who proves it
  /// is theirs with the end of the chassi — the plate alone is public.
  Future<OwnedVehicle> claimVehicle(String plate, String chassiSuffix) async {
    final body = await _client.call('$_service/ClaimVehicle', {
      'plate': normalizePlate(plate),
      'chassiSuffix': chassiSuffix.trim().toUpperCase(),
    });
    return OwnedVehicle.fromJson(
      body['vehicle'] as Map<String, dynamic>? ?? const {},
    );
  }

  /// Publishes a note to the plate's history. [clientId] makes a retry
  /// return the note already published instead of a copy.
  Future<HistoryNote> addNote({
    required String plate,
    required String clientId,
    required DateTime doneOn,
    required String description,
    int? mileageKm,
    int? costCents,
  }) async {
    final body = await _client.call('$_service/AddMaintenanceNote', {
      'plate': normalizePlate(plate),
      'clientId': clientId,
      'doneOn': formatDay(doneOn),
      'description': description.trim(),
      'mileageKm': ?mileageKm,
      'costCents': ?costCents,
    });
    return HistoryNote.fromJson(
      body['note'] as Map<String, dynamic>? ?? const {},
    );
  }

  Future<void> deleteNote(String id) async {
    await _client.call('$_service/DeleteMaintenanceNote', {'id': id});
  }

  /// A note has one photo; when a lost response hid an upload that landed,
  /// the retry is told so and counts as done.
  Future<void> uploadNotePhoto({
    required String noteId,
    required List<int> bytes,
    required String contentType,
  }) async {
    try {
      await _client.upload(
        'v1/maintenance-notes/$noteId/photo',
        bytes: bytes,
        filename: 'foto.${contentType.split('/').last}',
        contentType: contentType,
      );
    } on ApiException catch (e) {
      if (e.code != ApiErrorCode.alreadyExists) rethrow;
    }
  }
}
