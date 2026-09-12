import '../api/api_client.dart';
import '../models/owner.dart';
import '../models/vehicle.dart';

/// Signup, sign-in and the bike list for the proprietário side.
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

  /// Links an already-registered bike to the signed-in owner.
  Future<OwnedVehicle> claimVehicle(String plate) async {
    final body = await _client.call('$_service/ClaimVehicle', {
      'plate': normalizePlate(plate),
    });
    return OwnedVehicle.fromJson(
      body['vehicle'] as Map<String, dynamic>? ?? const {},
    );
  }
}
