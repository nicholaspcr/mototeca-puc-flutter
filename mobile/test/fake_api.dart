import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mototeca/api/api_client.dart';
import 'package:mototeca/state/app_scope.dart';

/// An in-memory stand-in for the Go API, so widget tests exercise the real
/// screens, repositories and JSON parsing without a server.
///
/// Responses mirror the shapes verified end to end by scripts/e2e.sh.
class FakeApi {
  /// Every procedure called, in order — lets a test assert that a screen
  /// actually hit the backend.
  final calls = <String>[];

  /// The JSON body of the latest call to each procedure.
  final lastBody = <String, Map<String, dynamic>>{};

  /// Procedures that should fail, mapped to the Connect error to return.
  final failures = <String, ({int status, String code, String message})>{};

  /// Procedures in [failures] that fail only on their next call.
  final failOnce = <String>{};

  /// Response bodies that replace the default for a procedure.
  final responses = <String, Map<String, dynamic>>{};

  static const ownerJson = {
    'id': 'owner-1',
    'name': 'Marcos Souza',
    'phone': '31990001234',
  };

  static const ownedVehicleJson = {
    'vehicle': vehicleSummaryJson,
    'currentMileageKm': 18420,
    'serviceCount': 3,
    'lastService': recordJson,
    'reminder': 'Troca de óleo em 580 km',
    'reminderIsDue': true,
    'nextOilChangeKm': 19000,
    'oilChangeIntervalKm': 3000,
  };

  static const workshopJson = {
    'id': 'workshop-1',
    'cnpj': '11222333000181',
    'name': 'Oficina do Zé',
    'verified': false,
  };

  static const vehicleJson = {
    'id': 'vehicle-1',
    'plate': 'ABC1D23',
    'chassi': '9C2KC1670GR000001',
    'make': 'Honda',
    'model': 'CG 160 Start',
    'year': 2022,
  };

  static const vehicleSummaryJson = {
    'plate': 'ABC1D23',
    'make': 'Honda',
    'model': 'CG 160 Start',
    'year': 2022,
  };

  // Keyed 'r1' so the widget keys (record-r1, history-r1) stay stable.
  static const recordJson = {
    'id': 'r1',
    'vehicle': vehicleSummaryJson,
    'workshopName': 'Oficina do Zé',
    'mechanicName': 'José Carlos',
    'operations': [
      'SERVICE_TYPE_OIL_CHANGE',
      'SERVICE_TYPE_CHAIN_AND_SPROCKET',
    ],
    'mileageKm': 18420,
    'costCents': 24500,
    'notes': 'Óleo trocado, corrente lubrificada.',
    'parts': [
      {'name': 'Óleo 10w30', 'quantity': 1, 'costCents': 6200},
    ],
    'createdAt': '2026-06-02T12:00:00Z',
  };

  http.Client get client => MockClient((request) async {
    final procedure = request.url.path.replaceFirst('/', '');
    calls.add(procedure);
    if (request.body.startsWith('{')) {
      lastBody[procedure] = jsonDecode(request.body) as Map<String, dynamic>;
    }

    final failure = failures[procedure];
    if (failure != null) {
      if (failOnce.remove(procedure)) failures.remove(procedure);
      return _json({
        'code': failure.code,
        'message': failure.message,
      }, failure.status);
    }

    if (responses[procedure] case final body?) return _json(body);

    return switch (procedure) {
      'mototeca.workshop.v1.WorkshopService/CreateWorkshop' ||
      'mototeca.workshop.v1.WorkshopService/Login' => _json({
        'workshop': workshopJson,
        'token': 'fake-token',
      }),
      'mototeca.vehicle.v1.VehicleService/GetVehicleByPlate' ||
      'mototeca.vehicle.v1.VehicleService/CreateVehicle' => _json({
        'vehicle': vehicleJson,
      }),
      'mototeca.service.v1.ServiceRecordService/ListWorkshopServiceRecords' =>
        _json({
          'records': [recordJson],
          'countThisMonth': 1,
        }),
      'mototeca.service.v1.ServiceRecordService/ListServiceRecordsByPlate' =>
        _json({
          'vehicle': vehicleSummaryJson,
          'records': [recordJson],
        }),
      'mototeca.service.v1.ServiceRecordService/CreateServiceRecord' ||
      'mototeca.service.v1.ServiceRecordService/GetServiceRecord' => _json({
        'record': recordJson,
      }),
      'mototeca.service.v1.ServiceRecordService/ReviseServiceRecord' => _json({
        'record': {
          ...recordJson,
          'id': 'r2',
          'mileageKm': 18500,
          'revisesRecordId': 'r1',
        },
      }),
      'mototeca.owner.v1.OwnerService/CreateOwner' ||
      'mototeca.owner.v1.OwnerService/Login' => _json({
        'owner': ownerJson,
        'token': 'fake-owner-token',
      }),
      'mototeca.owner.v1.OwnerService/ListMyVehicles' => _json({
        'vehicles': [ownedVehicleJson],
      }),
      'mototeca.owner.v1.OwnerService/ClaimVehicle' => _json({
        'vehicle': ownedVehicleJson,
      }),
      _ => _json({
        'code': 'unimplemented',
        'message': 'no fake for $procedure',
      }, 501),
    };
  });

  /// An AppState wired to this fake, ready to hand to MototecaApp.
  AppState get state => AppState(
    client: ApiClient(baseUrl: 'http://fake', httpClient: client),
  );

  static http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
}
