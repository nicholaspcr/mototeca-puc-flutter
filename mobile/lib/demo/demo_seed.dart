part of 'demo_backend.dart';

extension _Seed on DemoBackend {
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

    // A note a previous owner left on the demo bike, so Consultar Placa shows
    // both kinds of history.
    _notes.add({
      'id': _id('note'),
      'vehicleId': (_vehicles.first)['id'],
      'ownerId': null,
      'clientId': 'seed',
      'doneOn': formatDay(today.subtract(const Duration(days: 150))),
      'description': 'Troca de óleo feita em casa, óleo 10w30.',
      'mileageKm': 14100,
      'costCents': 5200,
      'photoUrl': null,
    });
  }
}
