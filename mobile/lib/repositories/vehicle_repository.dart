import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/vehicle.dart';

class VehicleRepository {
  const VehicleRepository(this._client);

  final ApiClient _client;

  static const _service = 'mototeca.vehicle.v1.VehicleService';

  /// Returns null when the plate has no vehicle registered yet, which is a
  /// normal outcome of a search rather than an error to show the user.
  Future<Vehicle?> findByPlate(String plate) async {
    try {
      final body = await _client.call('$_service/GetVehicleByPlate', {
        'plate': normalizePlate(plate),
      });
      return Vehicle.fromJson(
        body['vehicle'] as Map<String, dynamic>? ?? const {},
      );
    } on ApiException catch (e) {
      if (e.code == ApiErrorCode.notFound) return null;
      rethrow;
    }
  }

  Future<Vehicle> create({
    required String plate,
    required String chassi,
    required String make,
    required String model,
    required int year,
  }) async {
    final body = await _client.call('$_service/CreateVehicle', {
      'plate': normalizePlate(plate),
      'chassi': chassi.trim().toUpperCase(),
      'make': make.trim(),
      'model': model.trim(),
      'year': year,
    });
    return Vehicle.fromJson(
      body['vehicle'] as Map<String, dynamic>? ?? const {},
    );
  }
}
