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

/// Captures the last request so tests can assert on what went over the wire.
class Recorder {
  late http.Request request;
  Map<String, dynamic> get body =>
      jsonDecode(request.body) as Map<String, dynamic>;
}

ApiClient clientReturning(
  Object responseBody, {
  int status = 200,
  Recorder? recorder,
}) {
  final mock = MockClient((request) async {
    recorder?.request = request;
    return http.Response(
      jsonEncode(responseBody),
      status,
      headers: {'content-type': 'application/json'},
    );
  });
  return ApiClient(baseUrl: 'http://test', httpClient: mock);
}

void main() {
  group('ApiClient', () {
    test('posts to the Connect procedure path with a JSON body', () async {
      final recorder = Recorder();
      final client = clientReturning({'ok': true}, recorder: recorder);

      await client.call('pkg.v1.Service/Method', {'a': 1});

      expect(recorder.request.method, 'POST');
      expect(recorder.request.url.toString(), 'http://test/pkg.v1.Service/Method');
      expect(recorder.request.headers['Content-Type'], contains('application/json'));
      expect(recorder.body, {'a': 1});
    });

    test('omits the Authorization header when signed out', () async {
      final recorder = Recorder();
      final client = clientReturning({}, recorder: recorder);

      await client.call('pkg.v1.Service/Method', {});

      expect(recorder.request.headers.containsKey('Authorization'), isFalse);
    });

    test('sends the bearer token once signed in', () async {
      final recorder = Recorder();
      final client = clientReturning({}, recorder: recorder)..authToken = 'tok-123';

      await client.call('pkg.v1.Service/Method', {});

      expect(recorder.request.headers['Authorization'], 'Bearer tok-123');
    });

    test('turns a Connect error body into a typed ApiException', () async {
      final client = clientReturning(
        {'code': 'invalid_argument', 'message': 'select at least one operation'},
        status: 400,
      );

      expect(
        () => client.call('pkg.v1.Service/Method', {}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', ApiErrorCode.invalidArgument)
              .having((e) => e.message, 'message', 'select at least one operation'),
        ),
      );
    });

    test('reports a transport failure as offline rather than a server error', () async {
      final client = ApiClient(
        baseUrl: 'http://test',
        httpClient: MockClient((_) async => throw const SocketExceptionStub()),
      );

      expect(
        () => client.call('pkg.v1.Service/Method', {}),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiErrorCode.unavailable)),
      );
    });

    test('does not crash on a non-JSON error page', () async {
      final client = ApiClient(
        baseUrl: 'http://test',
        httpClient: MockClient((_) async => http.Response('<html>502</html>', 502)),
      );

      expect(
        () => client.call('pkg.v1.Service/Method', {}),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('VehicleRepository', () {
    test('normalizes the plate before sending it', () async {
      final recorder = Recorder();
      final repo = VehicleRepository(
        clientReturning({
          'vehicle': {'id': '1', 'plate': 'ABC1D23', 'make': 'Honda', 'model': 'CG', 'year': 2022},
        }, recorder: recorder),
      );

      await repo.findByPlate(' abc-1d23 ');

      expect(recorder.body['plate'], 'ABC1D23');
    });

    test('returns null for an unregistered plate instead of throwing', () async {
      final repo = VehicleRepository(
        clientReturning({'code': 'not_found', 'message': 'vehicle not found'}, status: 404),
      );

      expect(await repo.findByPlate('ZZZ9Z99'), isNull);
    });

    test('rethrows errors that are not "not found"', () async {
      final repo = VehicleRepository(
        clientReturning({'code': 'invalid_argument', 'message': 'bad plate'}, status: 400),
      );

      expect(() => repo.findByPlate('!!'), throwsA(isA<ApiException>()));
    });
  });

  group('ServiceRecordRepository', () {
    test('sends operations as protobuf enum names', () async {
      final recorder = Recorder();
      final repo = ServiceRecordRepository(
        clientReturning({'record': _recordJson()}, recorder: recorder),
      );

      await repo.create(
        plate: 'abc1d23',
        operations: [ServiceOperation.oilChange, ServiceOperation.tires],
        mileageKm: 18420,
        costCents: 24500,
        parts: const [Part(name: 'Óleo', quantity: 1, costCents: 6200)],
      );

      expect(recorder.body['operations'], ['SERVICE_TYPE_OIL_CHANGE', 'SERVICE_TYPE_TIRES']);
      expect(recorder.body['costCents'], 24500);
      expect(recorder.body['parts'], [
        {'name': 'Óleo', 'quantity': 1, 'costCents': 6200},
      ]);
    });

    test('omits optional fields that are blank rather than sending empty strings', () async {
      final recorder = Recorder();
      final repo = ServiceRecordRepository(
        clientReturning({'record': _recordJson()}, recorder: recorder),
      );

      await repo.create(
        plate: 'abc1d23',
        operations: [ServiceOperation.tires],
        mileageKm: 100,
        mechanicName: '   ',
        notes: '',
      );

      expect(recorder.body.containsKey('mechanicName'), isFalse);
      expect(recorder.body.containsKey('notes'), isFalse);
      expect(recorder.body.containsKey('costCents'), isFalse);
    });

    test('parses a record, including money and the operation labels', () async {
      final repo = ServiceRecordRepository(clientReturning({'record': _recordJson()}));

      final record = await repo.byId('record-1');

      expect(record.operations, [ServiceOperation.oilChange, ServiceOperation.chainAndSprocket]);
      expect(record.operationsLabel, 'Troca de óleo e filtro, Corrente, relação e coroa');
      expect(record.formattedCost, r'R$ 245,00');
      expect(record.formattedDate, '02/06/2026');
      expect(record.vehicle.labelWithYear, 'Honda CG 160 Start (2022)');
    });

    test('ignores an operation the app does not know', () async {
      final json = _recordJson()..['operations'] = ['SERVICE_TYPE_OIL_CHANGE', 'SERVICE_TYPE_TELEPORT'];
      final repo = ServiceRecordRepository(clientReturning({'record': json}));

      final record = await repo.byId('record-1');

      expect(record.operations, [ServiceOperation.oilChange]);
    });

    test('returns null history for an unregistered plate', () async {
      final repo = ServiceRecordRepository(
        clientReturning({'code': 'not_found', 'message': 'no vehicle'}, status: 404),
      );

      expect(await repo.historyByPlate('ZZZ9Z99'), isNull);
    });

    test('reads the dashboard feed and its monthly count', () async {
      final repo = ServiceRecordRepository(
        clientReturning({'records': [_recordJson()], 'countThisMonth': 7}),
      );

      final feed = await repo.workshopFeed();

      expect(feed.records, hasLength(1));
      expect(feed.countThisMonth, 7);
    });
  });

  group('WorkshopRepository', () {
    test('strips CNPJ punctuation before sending', () async {
      final recorder = Recorder();
      final repo = WorkshopRepository(
        clientReturning({
          'workshop': {'id': 'w1', 'cnpj': '11222333000181', 'name': 'Oficina'},
          'token': 'tok',
        }, recorder: recorder),
      );

      final session = await repo.login(cnpj: '11.222.333/0001-81', password: 'senha-forte-123');

      expect(recorder.body['cnpj'], '11222333000181');
      expect(session.token, 'tok');
      expect(session.workshop.name, 'Oficina');
    });

    test('surfaces a rejected sign-in as unauthenticated', () async {
      final repo = WorkshopRepository(
        clientReturning(
          {'code': 'unauthenticated', 'message': 'CNPJ ou senha inválidos'},
          status: 401,
        ),
      );

      expect(
        () => repo.login(cnpj: '11222333000181', password: 'errada'),
        throwsA(
          isA<ApiException>().having((e) => e.isSessionExpired, 'isSessionExpired', isTrue),
        ),
      );
    });
  });

  group('formatCents', () {
    test('renders cents as Brazilian currency without floating point', () {
      expect(formatCents(0), r'R$ 0,00');
      expect(formatCents(5), r'R$ 0,05');
      expect(formatCents(24500), r'R$ 245,00');
      expect(formatCents(100099), r'R$ 1000,99');
    });
  });
}

Map<String, dynamic> _recordJson() => {
  'id': 'record-1',
  'vehicle': {'plate': 'ABC1D23', 'make': 'Honda', 'model': 'CG 160 Start', 'year': 2022},
  'workshopName': 'Oficina do Zé',
  'mechanicName': 'José Carlos',
  'operations': ['SERVICE_TYPE_OIL_CHANGE', 'SERVICE_TYPE_CHAIN_AND_SPROCKET'],
  'mileageKm': 18420,
  'costCents': 24500,
  'notes': 'Óleo trocado.',
  'parts': [
    {'name': 'Óleo 10w30', 'quantity': 1, 'costCents': 6200},
  ],
  'createdAt': '2026-06-02T12:00:00Z',
};

/// A stand-in for a socket failure: MockClient can only throw, and ApiClient
/// treats any transport exception the same way.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
