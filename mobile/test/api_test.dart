import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mototeca/api/api_client.dart';
import 'package:mototeca/api/api_exception.dart';
import 'package:mototeca/models/service_operation.dart';
import 'package:mototeca/models/service_record.dart';
import 'package:mototeca/repositories/service_record_repository.dart';
import 'package:mototeca/repositories/vehicle_repository.dart';
import 'package:mototeca/repositories/workshop_repository.dart';

/// A client that answers [body] with [status] and keeps the requests it saw.
(ApiClient, List<http.Request>) serving(Object body, {int status = 200}) {
  final seen = <http.Request>[];
  final client = ApiClient(
    baseUrl: 'http://test',
    httpClient: MockClient((request) async {
      seen.add(request);
      return http.Response(
        body is String ? body : jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  return (client, seen);
}

Map<String, dynamic> sent(http.Request request) =>
    jsonDecode(request.body) as Map<String, dynamic>;

void main() {
  test('sends the bearer token only after sign-in', () async {
    final (client, seen) = serving({});

    await client.call('pkg.v1.Service/Method', {});
    client.authToken = 'tok-123';
    await client.call('pkg.v1.Service/Method', {});

    expect(seen[0].headers.containsKey('Authorization'), isFalse);
    expect(seen[1].headers['Authorization'], 'Bearer tok-123');
  });

  test('every failure reaches the screen as an ApiException', () async {
    final (rejected, _) = serving({
      'code': 'invalid_argument',
      'message': 'selecione ao menos uma operação',
    }, status: 400);
    final (htmlPage, _) = serving('<html>502</html>', status: 502);
    final offline = ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((_) async => throw Exception('socket closed')),
    );

    await expectLater(
      rejected.call('x/Y', {}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', ApiErrorCode.invalidArgument)
            .having((e) => e.message, 'message', contains('operação')),
      ),
    );
    await expectLater(htmlPage.call('x/Y', {}), throwsA(isA<ApiException>()));
    await expectLater(
      offline.call('x/Y', {}),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          ApiErrorCode.unavailable,
        ),
      ),
    );
  });

  test('an unknown plate is null; other errors still throw', () async {
    final (notFound, _) = serving({
      'code': 'not_found',
      'message': 'x',
    }, status: 404);
    final (badRequest, _) = serving({
      'code': 'invalid_argument',
      'message': 'x',
    }, status: 400);

    expect(await VehicleRepository(notFound).findByPlate('ZZZ9Z99'), isNull);
    expect(
      await ServiceRecordRepository(notFound).historyByPlate('ZZZ9Z99'),
      isNull,
    );
    await expectLater(
      VehicleRepository(badRequest).findByPlate('!!'),
      throwsA(isA<ApiException>()),
    );
  });

  test('requests carry normalized ids and protobuf enum names', () async {
    final (client, seen) = serving({
      'record': {'id': 'r1', 'operations': <String>[], 'mileageKm': 1},
      'workshop': {'id': 'w1', 'cnpj': '11222333000181', 'name': 'Oficina'},
      'token': 'tok',
    });

    await WorkshopRepository(client)
        .login(cnpj: '11.222.333/0001-81', password: 'senha-forte-123');
    await ServiceRecordRepository(client).create(
      plate: ' abc-1d23 ',
      operations: [ServiceOperation.oilChange, ServiceOperation.tires],
      mileageKm: 18420,
      mechanicName: '   ',
      parts: const [Part(name: 'Óleo', quantity: 1, costCents: 6200)],
    );

    expect(sent(seen[0])['cnpj'], '11222333000181');
    final record = sent(seen[1]);
    expect(record['plate'], 'ABC1D23');
    expect(record['operations'], [
      'SERVICE_TYPE_OIL_CHANGE',
      'SERVICE_TYPE_TIRES',
    ]);
    expect(record.containsKey('mechanicName'), isFalse);
    expect(record['parts'], [
      {'name': 'Óleo', 'quantity': 1, 'costCents': 6200},
    ]);
  });

  test('uploads are multipart; only photos carry a phase', () async {
    final (client, seen) = serving({'id': 'a1', 'url': 'u', 'kind': 'photo'});
    final records = ServiceRecordRepository(client);

    await records.uploadAttachment(
      recordId: 'r1',
      bytes: [1],
      filename: 'foto.png',
      contentType: 'image/png',
      phase: 'before',
    );
    await records.uploadAttachment(
      recordId: 'r1',
      bytes: [1],
      filename: 'nota.pdf',
      contentType: 'application/pdf',
      kind: 'invoice',
    );

    expect(seen[0].url.path, '/v1/service-records/r1/attachments');
    expect(seen[0].headers['content-type'], contains('multipart/form-data'));
    expect(seen[0].body, contains('name="phase"'));
    expect(seen[1].body, isNot(contains('name="phase"')));
  });

  test('an operation the app does not know is dropped', () async {
    final (client, _) = serving({
      'record': {
        'id': 'r1',
        'operations': ['SERVICE_TYPE_OIL_CHANGE', 'SERVICE_TYPE_TELEPORT'],
        'mileageKm': 1,
      },
    });

    final record = await ServiceRecordRepository(client).byId('r1');

    expect(record.operations, [ServiceOperation.oilChange]);
  });
}
