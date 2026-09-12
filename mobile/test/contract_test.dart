import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mototeca/api/api_client.dart';
import 'package:mototeca/api/api_exception.dart';
import 'package:mototeca/models/service_operation.dart';
import 'package:mototeca/repositories/service_record_repository.dart';
import 'package:mototeca/repositories/vehicle_repository.dart';
import 'package:mototeca/repositories/workshop_repository.dart';

/// Contract tests against JSON captured from the real Go API.
///
/// test/fixtures/*.json are verbatim responses recorded by scripts/e2e.sh
/// running against Postgres. The other tests use hand-written JSON, which can
/// drift from what the server actually sends — protobuf's JSON mapping
/// (camelCase names, enum values as strings, nanosecond timestamps, omitted
/// zero values) is easy to get subtly wrong by hand. Re-record the fixtures if
/// the proto changes.
ApiClient clientServing(String fixture, {int status = 200}) {
  final body = File('test/fixtures/$fixture').readAsStringSync();
  return ApiClient(
    baseUrl: 'http://fixture',
    httpClient: MockClient(
      (_) async => http.Response.bytes(
        utf8.encode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    ),
  );
}

void main() {
  test('parses a real Login response', () async {
    final session = await WorkshopRepository(
      clientServing('login.json'),
    ).login(cnpj: '11222333000181', password: 'senha-forte-123');

    expect(session.token, isNotEmpty);
    expect(session.workshop.name, 'Oficina do Zé');
    expect(session.workshop.cnpj, '11222333000181');
    // The server omits `verified` while it is false — proto3 drops zero
    // values, so the model must default rather than expect the key.
    expect(session.workshop.verified, isFalse);
  });

  test('parses a real rejected-login error', () async {
    final repo = WorkshopRepository(clientServing('login_error.json', status: 401));

    await expectLater(
      repo.login(cnpj: '11222333000181', password: 'errada'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', ApiErrorCode.unauthenticated)
            .having((e) => e.message, 'message', 'CNPJ ou senha inválidos'),
      ),
    );
  });

  test('parses a real GetVehicleByPlate response', () async {
    final vehicle = await VehicleRepository(
      clientServing('vehicle.json'),
    ).findByPlate('ABC1D23');

    expect(vehicle, isNotNull);
    expect(vehicle!.plate, 'ABC1D23');
    expect(vehicle.labelWithYear, 'Honda CG 160 Start (2022)');
    expect(vehicle.chassi, isNotEmpty);
  });

  test('parses a real plate-history response', () async {
    final history = await ServiceRecordRepository(
      clientServing('history.json'),
    ).historyByPlate('ABC1D23');

    expect(history, isNotNull);
    expect(history!.vehicle.plate, 'ABC1D23');
    expect(history.records, hasLength(1));

    final record = history.records.single;
    expect(record.operations, [
      ServiceOperation.oilChange,
      ServiceOperation.chainAndSprocket,
    ]);
    expect(record.workshopName, 'Oficina do Zé');
    expect(record.mechanicName, 'José Carlos');
    expect(record.mileageKm, 18420);
    expect(record.formattedCost, r'R$ 245,00');
    expect(record.parts, hasLength(2));
    expect(record.parts.first.costCents, isNotNull);
    // Sub-second precision in the timestamp must not break parsing.
    expect(record.createdAt.year, 2026);
  });

  test('parses a real workshop feed response', () async {
    final feed = await ServiceRecordRepository(
      clientServing('feed.json'),
    ).workshopFeed();

    expect(feed.records, hasLength(1));
    expect(feed.countThisMonth, 1);
    expect(feed.records.single.vehicle.label, 'Honda CG 160 Start');
  });
}
