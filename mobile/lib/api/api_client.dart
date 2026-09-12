import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';

/// Calls the Go backend over Connect's JSON mode.
///
/// Connect serves the same endpoints for gRPC and for plain HTTP+JSON, so a
/// unary RPC is just `POST /<package>.<Service>/<Method>` with a JSON body —
/// no generated Dart code, no separate REST layer (ARCHITECTURE.md section 5).
class ApiClient {
  ApiClient({String? baseUrl, http.Client? httpClient})
    : baseUrl = baseUrl ?? defaultBaseUrl,
      _http = httpClient ?? http.Client();

  /// Overridable at build time:
  /// `flutter run --dart-define=MOTOTECA_API_URL=http://10.0.2.2:8080`
  /// (10.0.2.2 is how the Android emulator reaches the host machine).
  static const defaultBaseUrl = String.fromEnvironment(
    'MOTOTECA_API_URL',
    defaultValue: 'http://localhost:8080',
  );

  final String baseUrl;
  final http.Client _http;

  /// Bearer token for the signed-in workshop, or null when anonymous. The
  /// public plate lookup deliberately works without one.
  String? authToken;

  static const _timeout = Duration(seconds: 15);

  /// Calls [procedure] (e.g. `mototeca.vehicle.v1.VehicleService/CreateVehicle`)
  /// and returns the decoded response body.
  Future<Map<String, dynamic>> call(
    String procedure,
    Map<String, dynamic> request,
  ) async {
    final uri = Uri.parse('$baseUrl/$procedure');
    final token = authToken;

    http.Response response;
    try {
      response = await _http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(request),
          )
          .timeout(_timeout);
    } on Exception {
      // Socket errors, DNS failures and timeouts are all "the server didn't
      // answer" as far as the user is concerned.
      throw const ApiException.offline();
    }

    final body = _decode(response.body);

    if (response.statusCode != 200) {
      throw ApiException(
        ApiErrorCode.parse(body['code'] as String?),
        body['message'] as String? ?? 'Falha na comunicação com o servidor.',
      );
    }
    return body;
  }

  Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) return const {};
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      // A proxy or error page rather than the API.
      return const {};
    }
  }

  void close() => _http.close();
}
