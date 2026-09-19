import 'dart:typed_data';

import '../models/vehicle.dart';

/// The demo's stand-in for the Go API: the same procedures, the same JSON,
/// the same refusals — all in memory, so the app runs with no backend and no
/// database (mobile/DEMO.md). State lives as long as the app does, so every
/// workflow that writes something shows the result everywhere else.
///
/// Wire shapes mirror proto/ and are asserted against the real server by
/// test/contract_test.dart, so a drift shows up as a failing test.
class DemoBackend {
  DemoBackend() {
    _seed();
  }

  /// Photo bytes picked during the demo, keyed by the `demo:` URL handed back
  /// in place of an object-storage link.
  final images = <String, Uint8List>{};

  final _workshops = <Map<String, dynamic>>[];
  final _owners = <Map<String, dynamic>>[];
  final _vehicles = <Map<String, dynamic>>[];
  final _records = <Map<String, dynamic>>[];
  var _sequence = 0;

  String _id(String prefix) => '$prefix-${++_sequence}';

  // --- Routing ---------------------------------------------------------------

  /// Answers one RPC. Throws [DemoFailure] for anything the API would refuse.
  Map<String, dynamic> call(
    String procedure,
    Map<String, dynamic> request,
    String? token,
  ) {
    return switch (procedure) {
      'mototeca.workshop.v1.WorkshopService/CreateWorkshop' => _createWorkshop(
        request,
      ),
      'mototeca.workshop.v1.WorkshopService/Login' => _workshopLogin(request),
      'mototeca.owner.v1.OwnerService/CreateOwner' => _createOwner(request),
      'mototeca.owner.v1.OwnerService/Login' => _ownerLogin(request),
      'mototeca.owner.v1.OwnerService/ListMyVehicles' => {
        'vehicles': [
          for (final vehicle in _vehicles)
            if (vehicle['ownerId'] == _ownerId(token))
              _ownedVehicleJson(vehicle),
        ],
      },
      'mototeca.owner.v1.OwnerService/ClaimVehicle' => _claimVehicle(
        request,
        token,
      ),
      'mototeca.owner.v1.OwnerService/ReleaseVehicle' => _releaseVehicle(
        request,
        token,
      ),
      'mototeca.vehicle.v1.VehicleService/CreateVehicle' => _createVehicle(
        request,
        token,
      ),
      'mototeca.vehicle.v1.VehicleService/GetVehicleByPlate' => _getVehicle(
        request,
        token,
      ),
      'mototeca.service.v1.ServiceRecordService/CreateServiceRecord' =>
        _createRecord(request, token),
      'mototeca.service.v1.ServiceRecordService/ReviseServiceRecord' =>
        _reviseRecord(request, token),
      'mototeca.service.v1.ServiceRecordService/GetServiceRecord' => {
        'record': _recordJson(_recordById(request['id'] as String? ?? '')),
      },
      'mototeca.service.v1.ServiceRecordService/ListServiceRecordsByPlate' =>
        _historyByPlate(request),
      'mototeca.service.v1.ServiceRecordService/ListWorkshopServiceRecords' =>
        _workshopFeed(request, token),
      _ => throw DemoFailure(
        501,
        'unimplemented',
        'procedimento não existe no modo demonstração',
      ),
    };
  }

  /// Answers the multipart upload route, keeping the bytes so the photo can be
  /// shown back without object storage.
  Map<String, dynamic> upload(
    String recordId,
    String? token, {
    required Uint8List bytes,
    required String kind,
    String? phase,
  }) {
    final workshopId = _workshopId(token);
    final record = _recordById(recordId);
    if (record['workshopId'] != workshopId) {
      throw DemoFailure(404, 'not_found', 'registro não encontrado');
    }

    final attachments = record['attachments'] as List<Map<String, dynamic>>;
    if (attachments.length >= 20) {
      throw DemoFailure(
        400,
        'invalid_argument',
        'um registro aceita até 20 arquivos',
      );
    }

    final id = _id('attachment');
    final url = 'demo:$id';
    images[url] = bytes;

    final stored = {
      'id': id,
      'url': url,
      'kind': kind,
      'phase': ?switch (phase) {
        'before' => 'PHOTO_PHASE_BEFORE',
        'after' => 'PHOTO_PHASE_AFTER',
        _ => null,
      },
    };
    attachments.add(stored);
    return stored;
  }

  // --- Workshops -------------------------------------------------------------

  Map<String, dynamic> _createWorkshop(Map<String, dynamic> request) {
    final cnpj = _digits(request['cnpj'] as String? ?? '');
    _requireValidCNPJ(cnpj);
    _requireText(request['name'], 'nome é obrigatório (até 120 caracteres)');
    _requirePassword(request['password'] as String? ?? '');

    if (_workshops.any((w) => w['cnpj'] == cnpj)) {
      throw DemoFailure(409, 'already_exists', 'este CNPJ já tem cadastro');
    }

    final workshop = {
      'id': _id('workshop'),
      'cnpj': cnpj,
      'name': (request['name'] as String).trim(),
      'password': request['password'] as String,
      'verified': false,
    };
    _workshops.add(workshop);
    return {
      'workshop': _workshopJson(workshop),
      'token': 'demo-w-${workshop['id']}',
    };
  }

  Map<String, dynamic> _workshopLogin(Map<String, dynamic> request) {
    // Empty fields sign in as the demo shop: on stage, "Entrar" should be one
    // tap. Typed-but-wrong credentials still fail, so the refusal is
    // demonstrable.
    if (_blankCredentials(request['cnpj'], request['password'])) {
      final demo = _workshops.first;
      return {'workshop': _workshopJson(demo), 'token': 'demo-w-${demo['id']}'};
    }

    final cnpj = _digits(request['cnpj'] as String? ?? '');
    final workshop = _workshops.where((w) => w['cnpj'] == cnpj).firstOrNull;
    if (workshop == null || workshop['password'] != request['password']) {
      throw DemoFailure(401, 'unauthenticated', 'CNPJ ou senha inválidos');
    }
    return {
      'workshop': _workshopJson(workshop),
      'token': 'demo-w-${workshop['id']}',
    };
  }

  // --- Owners ----------------------------------------------------------------

  Map<String, dynamic> _createOwner(Map<String, dynamic> request) {
    final phone = _digits(request['phone'] as String? ?? '');
    _requireText(request['name'], 'nome é obrigatório (até 120 caracteres)');
    if (phone.length != 10 && phone.length != 11) {
      throw DemoFailure(
        400,
        'invalid_argument',
        'telefone deve ter 10 ou 11 dígitos com DDD',
      );
    }
    _requirePassword(request['password'] as String? ?? '');

    if (_owners.any((o) => o['phone'] == phone)) {
      throw DemoFailure(409, 'already_exists', 'este celular já tem cadastro');
    }

    final owner = {
      'id': _id('owner'),
      'name': (request['name'] as String).trim(),
      'phone': phone,
      'password': request['password'] as String,
    };
    _owners.add(owner);
    return {'owner': _ownerJson(owner), 'token': 'demo-o-${owner['id']}'};
  }

  Map<String, dynamic> _ownerLogin(Map<String, dynamic> request) {
    if (_blankCredentials(request['phone'], request['password'])) {
      final demo = _owners.first;
      return {'owner': _ownerJson(demo), 'token': 'demo-o-${demo['id']}'};
    }

    final phone = _digits(request['phone'] as String? ?? '');
    final owner = _owners.where((o) => o['phone'] == phone).firstOrNull;
    if (owner == null || owner['password'] != request['password']) {
      throw DemoFailure(401, 'unauthenticated', 'celular ou senha inválidos');
    }
    return {'owner': _ownerJson(owner), 'token': 'demo-o-${owner['id']}'};
  }

  Map<String, dynamic> _claimVehicle(
    Map<String, dynamic> request,
    String? token,
  ) {
    final ownerId = _ownerId(token);
    final plate = normalizePlate(request['plate'] as String? ?? '');
    final suffix = (request['chassiSuffix'] as String? ?? '')
        .trim()
        .toUpperCase();
    if (suffix.length != chassiSuffixLength) {
      throw DemoFailure(
        400,
        'invalid_argument',
        'informe os $chassiSuffixLength últimos caracteres do chassi',
      );
    }

    final vehicle = _vehicles.where((v) => v['plate'] == plate).firstOrNull;
    if (vehicle == null) {
      throw DemoFailure(
        404,
        'not_found',
        'nenhuma moto cadastrada com esta placa',
      );
    }
    // Checked before ownership, exactly like the server: who holds a bike is
    // only revealed to someone with its papers.
    if (!(vehicle['chassi'] as String).endsWith(suffix)) {
      throw DemoFailure(
        403,
        'permission_denied',
        'o final do chassi não confere com esta placa',
      );
    }
    if (vehicle['ownerId'] != null && vehicle['ownerId'] != ownerId) {
      throw DemoFailure(
        400,
        'failed_precondition',
        'esta moto já está vinculada a outro proprietário',
      );
    }

    vehicle['ownerId'] = ownerId;
    return {'vehicle': _ownedVehicleJson(vehicle)};
  }

  Map<String, dynamic> _releaseVehicle(
    Map<String, dynamic> request,
    String? token,
  ) {
    final ownerId = _ownerId(token);
    final plate = normalizePlate(request['plate'] as String? ?? '');
    final vehicle = _vehicles
        .where((v) => v['plate'] == plate && v['ownerId'] == ownerId)
        .firstOrNull;
    if (vehicle == null) {
      throw DemoFailure(
        404,
        'not_found',
        'esta moto não está vinculada a você',
      );
    }
    vehicle['ownerId'] = null;
    return const {};
  }

  // --- Vehicles --------------------------------------------------------------

  Map<String, dynamic> _createVehicle(
    Map<String, dynamic> request,
    String? token,
  ) {
    _requireSession(token);
    final plate = normalizePlate(request['plate'] as String? ?? '');
    final chassi = (request['chassi'] as String? ?? '').trim().toUpperCase();
    final year = (request['year'] as num?)?.toInt() ?? 0;

    if (!RegExp(r'^[A-Z]{3}\d[A-Z0-9]\d{2}$').hasMatch(plate)) {
      throw DemoFailure(
        400,
        'invalid_argument',
        'placa inválida: use o formato ABC1234 ou ABC1D23',
      );
    }
    if (!RegExp(r'^[A-Z0-9]{17}$').hasMatch(chassi)) {
      throw DemoFailure(
        400,
        'invalid_argument',
        'chassi deve ter 17 letras ou números',
      );
    }
    _requireText(request['make'], 'marca é obrigatória (até 60 caracteres)');
    _requireText(request['model'], 'modelo é obrigatório (até 60 caracteres)');
    if (year < 1950 || year > DateTime.now().year + 1) {
      throw DemoFailure(
        400,
        'invalid_argument',
        'ano deve estar entre 1950 e ${DateTime.now().year + 1}',
      );
    }

    if (_vehicles.any((v) => v['plate'] == plate)) {
      throw DemoFailure(409, 'already_exists', 'esta placa já está cadastrada');
    }
    if (_vehicles.any((v) => v['chassi'] == chassi)) {
      throw DemoFailure(
        409,
        'already_exists',
        'este chassi já está cadastrado em outra placa',
      );
    }

    final vehicle = {
      'id': _id('vehicle'),
      'plate': plate,
      'chassi': chassi,
      'make': (request['make'] as String).trim(),
      'model': (request['model'] as String).trim(),
      'year': year,
      'ownerId': null,
    };
    _vehicles.add(vehicle);
    return {'vehicle': _vehicleJson(vehicle)};
  }

  Map<String, dynamic> _getVehicle(
    Map<String, dynamic> request,
    String? token,
  ) {
    _workshopId(token);
    final plate = normalizePlate(request['plate'] as String? ?? '');
    final vehicle = _vehicles.where((v) => v['plate'] == plate).firstOrNull;
    if (vehicle == null) {
      throw DemoFailure(
        404,
        'not_found',
        'nenhuma moto cadastrada com esta placa',
      );
    }
    return {'vehicle': _vehicleJson(vehicle)};
  }

  // --- Service records -------------------------------------------------------

  Map<String, dynamic> _createRecord(
    Map<String, dynamic> request,
    String? token,
  ) {
    final workshop = _workshopById(_workshopId(token));
    final plate = normalizePlate(request['plate'] as String? ?? '');
    final vehicle = _vehicles.where((v) => v['plate'] == plate).firstOrNull;
    if (vehicle == null) {
      throw DemoFailure(
        404,
        'not_found',
        'moto não cadastrada — cadastre a placa antes',
      );
    }

    final mileageKm = _validDraft(request);
    if (request['confirmLowerMileage'] != true) {
      final highest = _currentRecords(plate)
          .map((r) => r['mileageKm'] as int)
          .fold<int?>(null, (a, b) => a == null || b > a ? b : a);
      if (highest != null && mileageKm < highest) {
        throw DemoFailure(
          400,
          'failed_precondition',
          'quilometragem menor que a última registrada para esta moto '
              '($highest km)',
        );
      }
    }

    final record = _newRecord(request, workshop, plate);
    _records.add(record);
    return {'record': _recordJson(record)};
  }

  Map<String, dynamic> _reviseRecord(
    Map<String, dynamic> request,
    String? token,
  ) {
    final workshop = _workshopById(_workshopId(token));
    final original = _recordById(request['recordId'] as String? ?? '');
    if (original['workshopId'] != workshop['id']) {
      throw DemoFailure(404, 'not_found', 'registro não encontrado');
    }
    if (original['supersededByRecordId'] != null) {
      throw DemoFailure(
        400,
        'failed_precondition',
        'este registro já foi corrigido — revise a correção',
      );
    }
    _validDraft(request);

    // A correction stays on the same bike and keeps the original's files.
    final correction =
        _newRecord(request, workshop, original['plate'] as String)
          ..['revisesRecordId'] = original['id']
          ..['attachments'] = [
            ...(original['attachments'] as List<Map<String, dynamic>>),
          ];
    original['supersededByRecordId'] = correction['id'];
    _records.add(correction);
    return {'record': _recordJson(correction)};
  }

  Map<String, dynamic> _historyByPlate(Map<String, dynamic> request) {
    final plate = normalizePlate(request['plate'] as String? ?? '');
    final vehicle = _vehicles.where((v) => v['plate'] == plate).firstOrNull;
    if (vehicle == null) {
      throw DemoFailure(
        404,
        'not_found',
        'nenhuma moto cadastrada com esta placa',
      );
    }
    return {
      'vehicle': _summaryJson(vehicle),
      'records': [for (final r in _currentRecords(plate)) _recordJson(r)],
    };
  }

  Map<String, dynamic> _workshopFeed(
    Map<String, dynamic> request,
    String? token,
  ) {
    final workshopId = _workshopId(token);
    final limit = (request['limit'] as num?)?.toInt() ?? 50;
    final mine =
        _records
            .where(
              (r) =>
                  r['workshopId'] == workshopId &&
                  r['supersededByRecordId'] == null,
            )
            .toList()
          ..sort(
            (a, b) => (b['createdAt'] as DateTime).compareTo(
              a['createdAt'] as DateTime,
            ),
          );

    final month = DateTime.now();
    final startOfMonth = DateTime(month.year, month.month);
    return {
      'records': [
        for (final r in mine.take(limit <= 0 ? 50 : limit)) _recordJson(r),
      ],
      'countThisMonth': mine
          .where((r) => (r['createdAt'] as DateTime).isAfter(startOfMonth))
          .length,
    };
  }

  /// Shared by a new record and a correction: both are records.
  Map<String, dynamic> _newRecord(
    Map<String, dynamic> request,
    Map<String, dynamic> workshop,
    String plate,
  ) {
    return {
      'id': _id('record'),
      'plate': plate,
      'workshopId': workshop['id'],
      'workshopName': workshop['name'],
      'mechanicName': request['mechanicName'],
      'operations': [...(request['operations'] as List<dynamic>? ?? const [])],
      'mileageKm': (request['mileageKm'] as num?)?.toInt() ?? 0,
      'costCents': (request['costCents'] as num?)?.toInt(),
      'notes': request['notes'],
      'parts': [
        for (final part in request['parts'] as List<dynamic>? ?? const [])
          {...part as Map<String, dynamic>},
      ],
      'attachments': <Map<String, dynamic>>[],
      'createdAt': DateTime.now(),
      'revisesRecordId': null,
      'supersededByRecordId': null,
    };
  }

  int _validDraft(Map<String, dynamic> request) {
    final operations = request['operations'] as List<dynamic>? ?? const [];
    if (operations.isEmpty) {
      throw DemoFailure(
        400,
        'invalid_argument',
        'selecione ao menos uma operação',
      );
    }
    final mileageKm = (request['mileageKm'] as num?)?.toInt() ?? 0;
    if (mileageKm < 0 || mileageKm > 2000000) {
      throw DemoFailure(
        400,
        'invalid_argument',
        'quilometragem deve estar entre 0 e 2000000 km',
      );
    }
    return mileageKm;
  }

  List<Map<String, dynamic>> _currentRecords(String plate) {
    final current = _records
        .where((r) => r['plate'] == plate && r['supersededByRecordId'] == null)
        .toList();
    current.sort(
      (a, b) =>
          (b['createdAt'] as DateTime).compareTo(a['createdAt'] as DateTime),
    );
    return current;
  }

  Map<String, dynamic> _recordById(String id) {
    final record = _records.where((r) => r['id'] == id).firstOrNull;
    if (record == null) {
      throw DemoFailure(404, 'not_found', 'registro não encontrado');
    }
    return record;
  }

  // --- JSON ------------------------------------------------------------------

  Map<String, dynamic> _workshopJson(Map<String, dynamic> w) => {
    'id': w['id'],
    'cnpj': w['cnpj'],
    'name': w['name'],
    'verified': w['verified'],
  };

  Map<String, dynamic> _ownerJson(Map<String, dynamic> o) => {
    'id': o['id'],
    'name': o['name'],
    'phone': o['phone'],
  };

  Map<String, dynamic> _vehicleJson(Map<String, dynamic> v) => {
    'id': v['id'],
    'plate': v['plate'],
    'chassi': v['chassi'],
    'make': v['make'],
    'model': v['model'],
    'year': v['year'],
  };

  /// What the public lookup returns: no chassi, no owner.
  Map<String, dynamic> _summaryJson(Map<String, dynamic> v) => {
    'plate': v['plate'],
    'make': v['make'],
    'model': v['model'],
    'year': v['year'],
  };

  Map<String, dynamic> _recordJson(Map<String, dynamic> r) {
    final vehicle = _vehicles.firstWhere((v) => v['plate'] == r['plate']);
    return {
      'id': r['id'],
      'vehicle': _summaryJson(vehicle),
      'workshopName': r['workshopName'],
      'mechanicName': r['mechanicName'],
      'operations': r['operations'],
      'mileageKm': r['mileageKm'],
      'costCents': r['costCents'],
      'notes': r['notes'],
      'parts': r['parts'],
      'attachments': r['attachments'],
      'createdAt': (r['createdAt'] as DateTime).toUtc().toIso8601String(),
      'revisesRecordId': r['revisesRecordId'],
      'supersededByRecordId': r['supersededByRecordId'],
    };
  }

  Map<String, dynamic> _ownedVehicleJson(Map<String, dynamic> v) {
    final history = _currentRecords(v['plate'] as String);
    final mileages = history.map((r) => r['mileageKm'] as int);
    final currentKm = mileages.isEmpty
        ? 0
        : mileages.reduce((a, b) => a > b ? a : b);
    final oilChanges = history.where(
      (r) => (r['operations'] as List).contains('SERVICE_TYPE_OIL_CHANGE'),
    );
    final lastOilKm = oilChanges.isEmpty
        ? null
        : oilChanges
              .map((r) => r['mileageKm'] as int)
              .reduce((a, b) => a > b ? a : b);
    final reminder = _reminder(
      serviceCount: history.length,
      currentKm: currentKm,
      lastOilKm: lastOilKm,
    );

    return {
      'vehicle': _summaryJson(v),
      'currentMileageKm': currentKm,
      'serviceCount': history.length,
      'lastService': ?history.isEmpty ? null : _recordJson(history.first),
      'reminder': reminder.text,
      'reminderIsDue': reminder.isDue,
      'nextOilChangeKm': reminder.dueAtKm,
      'oilChangeIntervalKm': reminder.dueAtKm > 0 ? oilChangeIntervalKm : 0,
    };
  }

  /// The same rule the Go side applies (internal/owner/reminder.go).
  ({String text, bool isDue, int dueAtKm}) _reminder({
    required int serviceCount,
    required int currentKm,
    required int? lastOilKm,
  }) {
    if (lastOilKm == null) {
      return serviceCount == 0
          ? (text: 'Sem serviços registrados', isDue: false, dueAtKm: 0)
          : (text: 'Sem troca de óleo registrada', isDue: true, dueAtKm: 0);
    }

    final dueAt = lastOilKm + oilChangeIntervalKm;
    final remaining = dueAt - currentKm;
    if (remaining <= 0) {
      return (
        text: 'Troca de óleo atrasada em ${-remaining} km',
        isDue: true,
        dueAtKm: dueAt,
      );
    }
    if (remaining <= 600) {
      return (
        text: 'Troca de óleo em $remaining km',
        isDue: true,
        dueAtKm: dueAt,
      );
    }
    return (
      text: 'Em dia · próxima troca em $remaining km',
      isDue: false,
      dueAtKm: dueAt,
    );
  }

  // --- Sessions and validation ----------------------------------------------

  String _requireSession(String? token) {
    if (token == null || !token.startsWith('demo-')) {
      throw DemoFailure(401, 'unauthenticated', 'entre para continuar');
    }
    return token;
  }

  String _workshopId(String? token) {
    if (token == null || !token.startsWith('demo-w-')) {
      throw DemoFailure(
        401,
        'unauthenticated',
        'entre como oficina para continuar',
      );
    }
    return token.substring('demo-w-'.length);
  }

  String _ownerId(String? token) {
    if (token == null || !token.startsWith('demo-o-')) {
      throw DemoFailure(
        401,
        'unauthenticated',
        'entre como proprietário para continuar',
      );
    }
    return token.substring('demo-o-'.length);
  }

  Map<String, dynamic> _workshopById(String id) =>
      _workshops.firstWhere((w) => w['id'] == id);

  void _requireText(Object? value, String message) {
    if (value is! String || value.trim().isEmpty) {
      throw DemoFailure(400, 'invalid_argument', message);
    }
  }

  void _requirePassword(String password) {
    if (password.length < 8) {
      throw DemoFailure(
        400,
        'invalid_argument',
        'senha deve ter ao menos 8 caracteres',
      );
    }
  }

  void _requireValidCNPJ(String cnpj) {
    if (cnpj.length != 14 || !_checkDigitsMatch(cnpj)) {
      throw DemoFailure(400, 'invalid_argument', 'CNPJ inválido');
    }
  }

  /// The two check digits, the same maths the backend runs.
  bool _checkDigitsMatch(String cnpj) {
    final digits = [for (final c in cnpj.split('')) int.parse(c)];
    if (digits.every((d) => d == digits.first)) return false;

    int check(int upTo, List<int> weights) {
      var sum = 0;
      for (var i = 0; i < upTo; i++) {
        sum += digits[i] * weights[i];
      }
      final remainder = sum % 11;
      return remainder < 2 ? 0 : 11 - remainder;
    }

    return digits[12] == check(12, [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]) &&
        digits[13] == check(13, [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]);
  }

  bool _blankCredentials(Object? account, Object? password) =>
      (account as String? ?? '').trim().isEmpty &&
      (password as String? ?? '').trim().isEmpty;

  String _digits(String raw) => raw.replaceAll(RegExp(r'\D'), '');

  // --- Seed ------------------------------------------------------------------

  /// Enough history for every screen to look real on the first tap: two shops,
  /// two bikes, one of them already the demo owner's.
  void _seed() {
    final ze = {
      'id': _id('workshop'),
      'cnpj': demoCNPJ,
      'name': 'Oficina do Zé',
      'password': demoPassword,
      'verified': true,
    };
    final center = {
      'id': _id('workshop'),
      'cnpj': '11444555000149',
      'name': 'Moto Center BH',
      'password': demoPassword,
      'verified': false,
    };
    _workshops.addAll([ze, center]);

    final marcos = {
      'id': _id('owner'),
      'name': 'Marcos Souza',
      'phone': demoPhone,
      'password': demoPassword,
    };
    _owners.add(marcos);

    _vehicles.addAll([
      {
        'id': _id('vehicle'),
        'plate': demoPlate,
        'chassi': demoChassi,
        'make': 'Honda',
        'model': 'CG 160 Start',
        'year': 2022,
        'ownerId': null,
      },
      {
        'id': _id('vehicle'),
        'plate': 'KLM3C45',
        'chassi': '9C6KG0710M0000002',
        'make': 'Yamaha',
        'model': 'Factor 150',
        'year': 2021,
        'ownerId': marcos['id'],
      },
    ]);

    final today = DateTime.now();
    void seedRecord({
      required Map<String, dynamic> workshop,
      required String plate,
      required List<String> operations,
      required int mileageKm,
      required int daysAgo,
      String? mechanicName,
      int? costCents,
      String? notes,
      List<Map<String, dynamic>> parts = const [],
    }) {
      _records.add({
        'id': _id('record'),
        'plate': plate,
        'workshopId': workshop['id'],
        'workshopName': workshop['name'],
        'mechanicName': mechanicName,
        'operations': operations,
        'mileageKm': mileageKm,
        'costCents': costCents,
        'notes': notes,
        'parts': parts,
        'attachments': <Map<String, dynamic>>[],
        'createdAt': today.subtract(Duration(days: daysAgo)),
        'revisesRecordId': null,
        'supersededByRecordId': null,
      });
    }

    // The demo bike, serviced by both shops — the point of the product.
    seedRecord(
      workshop: center,
      plate: demoPlate,
      operations: ['SERVICE_TYPE_SCHEDULED_REVIEW', 'SERVICE_TYPE_BRAKES'],
      mileageKm: 12400,
      daysAgo: 208,
      mechanicName: 'Paulo Nunes',
      costCents: 31000,
      notes: 'Revisão dos 12.000 km e pastilhas dianteiras trocadas.',
      parts: [
        {'name': 'Pastilha de freio', 'quantity': 2, 'costCents': 9800},
      ],
    );
    seedRecord(
      workshop: ze,
      plate: demoPlate,
      operations: [
        'SERVICE_TYPE_OIL_CHANGE',
        'SERVICE_TYPE_CHAIN_AND_SPROCKET',
      ],
      mileageKm: 16150,
      daysAgo: 96,
      mechanicName: 'José Carlos',
      costCents: 24500,
      notes: 'Óleo 10w30 trocado, corrente lubrificada e ajustada.',
      parts: [
        {'name': 'Óleo 10w30', 'quantity': 1, 'costCents': 6200},
        {'name': 'Kit relação', 'quantity': 1, 'costCents': 14500},
      ],
    );
    seedRecord(
      workshop: ze,
      plate: demoPlate,
      operations: ['SERVICE_TYPE_TIRES'],
      mileageKm: 18420,
      daysAgo: 12,
      mechanicName: 'José Carlos',
      costCents: 48000,
      notes: 'Pneu traseiro substituído; dianteiro com 60% de vida.',
      parts: [
        {'name': 'Pneu traseiro 90/90-18', 'quantity': 1, 'costCents': 38000},
      ],
    );

    // The owner's own bike, due for an oil change — Lembretes has something
    // to show the moment they sign in.
    seedRecord(
      workshop: ze,
      plate: 'KLM3C45',
      operations: ['SERVICE_TYPE_OIL_CHANGE'],
      mileageKm: 21300,
      daysAgo: 150,
      mechanicName: 'José Carlos',
      costCents: 18000,
    );
    seedRecord(
      workshop: center,
      plate: 'KLM3C45',
      operations: ['SERVICE_TYPE_ELECTRICAL'],
      mileageKm: 23900,
      daysAgo: 30,
      mechanicName: 'Paulo Nunes',
      costCents: 22000,
      notes: 'Bateria substituída.',
    );
  }
}

/// Credentials printed on the login screen in demo mode.
const demoCNPJ = '11222333000181';
const demoPhone = '31990001234';
const demoPassword = 'senha-forte-123';
const demoPlate = 'ABC1D23';
const demoChassi = '9C2KC1670GR000001';

/// Matches the backend's OilChangeIntervalKm.
const oilChangeIntervalKm = 3000;

/// A refusal the demo backend answers with, in the Connect error shape.
class DemoFailure implements Exception {
  DemoFailure(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;
}
