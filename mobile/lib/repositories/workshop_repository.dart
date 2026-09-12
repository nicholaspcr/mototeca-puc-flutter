import '../api/api_client.dart';
import '../models/workshop.dart';

/// Signup and sign-in for the oficina side.
class WorkshopRepository {
  const WorkshopRepository(this._client);

  final ApiClient _client;

  static const _service = 'mototeca.workshop.v1.WorkshopService';

  Future<WorkshopSession> createWorkshop({
    required String cnpj,
    required String name,
    required String password,
    String? address,
  }) async {
    final body = await _client.call('$_service/CreateWorkshop', {
      'cnpj': normalizeCnpj(cnpj),
      'name': name.trim(),
      'password': password,
      if (address != null && address.trim().isNotEmpty) 'address': address.trim(),
    });
    return WorkshopSession.fromJson(body);
  }

  Future<WorkshopSession> login({
    required String cnpj,
    required String password,
  }) async {
    final body = await _client.call('$_service/Login', {
      'cnpj': normalizeCnpj(cnpj),
      'password': password,
    });
    return WorkshopSession.fromJson(body);
  }
}
