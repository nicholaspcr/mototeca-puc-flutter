import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'api_exception.dart';

/// Calls the Go backend over Connect's JSON mode: a unary RPC is just
/// `POST /<package>.<Service>/<Method>` with a JSON body, so no generated
/// Dart code and no separate REST layer (ARCHITECTURE.md §5).
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

  /// Bearer token for the signed-in account, or null when anonymous. The
  /// public plate lookup deliberately works without one.
  String? authToken;

  /// Called when the server rejects the token. Set by [AppState] so an expired
  /// session is handled once, not by every screen that happens to catch it.
  void Function()? onUnauthenticated;

  static const _timeout = Duration(seconds: 15);
  // Photos are far larger than an RPC body, and often on a shop's poor
  // connection (ARCHITECTURE.md §9).
  static const _uploadTimeout = Duration(seconds: 60);

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
      // Socket, DNS and timeout all read as "the server didn't answer".
      throw const ApiException.offline();
    }

    final body = _decode(response.body);

    if (response.statusCode != 200) {
      final error = ApiException(
        ApiErrorCode.parse(body['code'] as String?),
        body['message'] as String? ?? 'Falha na comunicação com o servidor.',
      );
      if (error.isSessionExpired && token != null) onUnauthenticated?.call();
      throw error;
    }
    return body;
  }

  /// Uploads one file to a plain multipart route (not an RPC — see the Go
  /// side for why) and returns the decoded response.
  Future<Map<String, dynamic>> upload(
    String path, {
    required List<int> bytes,
    required String filename,
    required String contentType,
    Map<String, String> fields = const {},
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/$path'))
      ..fields.addAll(fields)
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: MediaType.parse(contentType),
        ),
      );

    final token = authToken;
    if (token != null) request.headers['Authorization'] = 'Bearer $token';

    http.Response response;
    try {
      // Send through this client, not request.send(), which would create its
      // own and ignore everything configured here.
      response = await http.Response.fromStream(await _http.send(request))
          .timeout(_uploadTimeout);
    } on Exception {
      throw const ApiException.offline();
    }

    final body = _decode(response.body);
    if (response.statusCode != 200) {
      final error = ApiException(
        ApiErrorCode.parse(body['code'] as String?),
        body['message'] as String? ?? 'Falha ao enviar o arquivo.',
      );
      if (error.isSessionExpired && token != null) onUnauthenticated?.call();
      throw error;
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
