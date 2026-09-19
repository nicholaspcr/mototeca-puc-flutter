import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../api/api_client.dart';
import 'demo_backend.dart';

/// True unless the app was built against a real API. Flipping it needs no
/// code change:
///   flutter run -d chrome                                   → demo data
///   flutter run --dart-define=MOTOTECA_API_URL=http://…     → the Go backend
const demoMode = bool.fromEnvironment(
  'MOTOTECA_DEMO',
  defaultValue: !bool.hasEnvironment('MOTOTECA_API_URL'),
);

/// The demo's data, shared by the client and by the photo widgets that show
/// back what was just picked. Created on first use, so a build against the
/// real API never touches it.
final demoBackend = DemoBackend();

/// The API client the app runs with.
ApiClient createApiClient() => demoMode
    ? ApiClient(baseUrl: 'demo://mototeca', httpClient: DemoClient())
    : ApiClient();

/// Serves [demoBackend] over the same HTTP surface as the real API, so every
/// screen, repository and error path runs its normal code.
class DemoClient extends http.BaseClient {
  DemoClient({
    DemoBackend? backend,
    this.latency = const Duration(milliseconds: 140),
  }) : backend = backend ?? demoBackend;

  /// Its own data, so a test starts from the seed instead of whatever the
  /// last one wrote.
  final DemoBackend backend;

  /// Kept short but non-zero: the spinners and disabled buttons are part of
  /// what the app looks like.
  final Duration latency;

  static final _uploadPath = RegExp(
    r'^/?v1/service-records/([^/]+)/attachments$',
  );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await Future<void>.delayed(latency);

    final token = request.headers['Authorization']?.replaceFirst('Bearer ', '');
    try {
      final body = switch (_uploadPath.firstMatch(request.url.path)) {
        final match? => await _upload(match.group(1)!, token, request),
        null => backend.call(
          request.url.path.replaceFirst('/', ''),
          await _json(request),
          token,
        ),
      };
      return _response(200, body);
    } on DemoFailure catch (failure) {
      return _response(failure.status, {
        'code': failure.code,
        'message': failure.message,
      });
    }
  }

  Future<Map<String, dynamic>> _upload(
    String recordId,
    String? token,
    http.BaseRequest request,
  ) async {
    if (request is! http.MultipartRequest || request.files.isEmpty) {
      throw DemoFailure(
        400,
        'invalid_argument',
        'envie o arquivo como multipart/form-data',
      );
    }

    final file = request.files.first;
    return backend.upload(
      recordId,
      token,
      bytes: Uint8List.fromList(
        await file.finalize().expand((c) => c).toList(),
      ),
      kind: request.fields['kind'] ?? 'photo',
      phase: request.fields['phase'],
    );
  }

  Future<Map<String, dynamic>> _json(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    if (body.isEmpty) return const {};
    return jsonDecode(body) as Map<String, dynamic>;
  }

  http.StreamedResponse _response(int status, Map<String, dynamic> body) {
    final bytes = utf8.encode(jsonEncode(body));
    return http.StreamedResponse(
      Stream.value(bytes),
      status,
      contentLength: bytes.length,
      headers: const {'content-type': 'application/json'},
    );
  }
}
