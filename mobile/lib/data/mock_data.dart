/// Sample data mirroring the mockups in `design/`. Replaced by the Go API
/// (Connect-RPC over HTTP+JSON) once the client layer lands.
library;

class Part {
  const Part({required this.name, required this.quantity, required this.cost});

  final String name;
  final String quantity;
  final double cost;
}

class ServiceRecord {
  const ServiceRecord({
    required this.id,
    required this.date,
    required this.workshop,
    required this.mechanic,
    required this.operations,
    required this.mileageKm,
    required this.cost,
    required this.notes,
    this.parts = const [],
  });

  final String id;
  final String date;
  final String workshop;
  final String mechanic;
  final List<String> operations;
  final int mileageKm;
  final double cost;
  final String notes;
  final List<Part> parts;

  String get operationsLabel => operations.join(', ');
}

class Vehicle {
  const Vehicle({
    required this.plate,
    required this.make,
    required this.model,
    required this.year,
    required this.color,
    required this.owner,
    required this.mileageKm,
    required this.history,
    this.reminder,
    this.reminderIsDue = false,
  });

  final String plate;
  final String make;
  final String model;
  final int year;
  final String color;
  final String owner;
  final int mileageKm;
  final List<ServiceRecord> history;

  /// Short status shown on "Minhas Motos" — null when nothing is due.
  final String? reminder;
  final bool reminderIsDue;

  String get label => '$make $model';
  String get labelWithYear => '$make $model ($year)';
}

/// The fixed operation taxonomy (ARCHITECTURE.md §3).
const operationTaxonomy = <String>[
  'Troca de óleo e filtro',
  'Revisão programada',
  'Freios (pastilhas, discos, fluido)',
  'Corrente, relação e coroa',
  'Pneus',
  'Elétrica / bateria',
  'Velas / ignição',
  'Suspensão',
  'Embreagem',
  'Carburação / injeção eletrônica',
  'Funilaria / pintura',
  'Outro',
];

const _cg160History = <ServiceRecord>[
  ServiceRecord(
    id: 'r1',
    date: '02/06/2026',
    workshop: 'Oficina do Zé',
    mechanic: 'José Carlos',
    operations: ['Troca de óleo e filtro', 'Corrente, relação e coroa'],
    mileageKm: 18420,
    cost: 245,
    notes:
        'Óleo 10w30 semissintético trocado, corrente limpa e lubrificada. '
        'Recomendada revisão da suspensão na próxima visita.',
    parts: [
      Part(name: 'Óleo 10w30 semissintético', quantity: '1L', cost: 62),
      Part(name: 'Filtro de óleo', quantity: '1un', cost: 38),
      Part(name: 'Kit relação', quantity: '1un', cost: 145),
    ],
  ),
  ServiceRecord(
    id: 'r2',
    date: '14/02/2026',
    workshop: 'Moto Center Silva',
    mechanic: 'Carlos Silva',
    operations: ['Freios (pastilhas, discos, fluido)'],
    mileageKm: 16100,
    cost: 180,
    notes: 'Pastilhas dianteira e traseira substituídas, fluido de freio verificado.',
  ),
  ServiceRecord(
    id: 'r3',
    date: '30/09/2025',
    workshop: 'Oficina do Zé',
    mechanic: 'José Carlos',
    operations: ['Revisão programada'],
    mileageKm: 13500,
    cost: 150,
    notes: 'Revisão programada dos 13 mil km, nenhuma pendência encontrada.',
  ),
];

const _fazerHistory = <ServiceRecord>[
  ServiceRecord(
    id: 'r4',
    date: '28/05/2026',
    workshop: 'Oficina do Zé',
    mechanic: 'José Carlos',
    operations: ['Pneus', 'Suspensão'],
    mileageKm: 32180,
    cost: 620,
    notes: 'Par de pneus trocado, suspensão dianteira regulada.',
  ),
  ServiceRecord(
    id: 'r5',
    date: '11/01/2026',
    workshop: 'Auto Peças e Motos Ipiranga',
    mechanic: 'Roberto Nunes',
    operations: ['Velas / ignição', 'Elétrica / bateria'],
    mileageKm: 29800,
    cost: 210,
    notes: 'Velas trocadas, bateria testada e recarregada.',
  ),
];

const mockVehicles = <Vehicle>[
  Vehicle(
    plate: 'ABC1D23',
    make: 'Honda',
    model: 'CG 160 Start',
    year: 2022,
    color: 'Vermelha',
    owner: 'Marcos Vinícius Souza',
    mileageKm: 18420,
    history: _cg160History,
    reminder: 'Troca de óleo em 580 km',
    reminderIsDue: true,
  ),
  Vehicle(
    plate: 'BRA2E19',
    make: 'Yamaha',
    model: 'Fazer 250',
    year: 2021,
    color: 'Preta',
    owner: 'Marcos Vinícius Souza',
    mileageKm: 32180,
    history: _fazerHistory,
    reminder: 'Em dia',
  ),
];

/// Records created by the logged-in workshop — the dashboard feed is scoped to
/// the shop, not to the vehicle (ARCHITECTURE.md §3.3).
const currentWorkshop = 'Oficina do Zé';

Vehicle? findVehicleByPlate(String plate) {
  final normalized = plate.trim().toUpperCase().replaceAll('-', '');
  for (final vehicle in mockVehicles) {
    if (vehicle.plate == normalized) return vehicle;
  }
  return null;
}

List<({Vehicle vehicle, ServiceRecord record})> workshopRecords() {
  final entries = <({Vehicle vehicle, ServiceRecord record})>[];
  for (final vehicle in mockVehicles) {
    for (final record in vehicle.history) {
      if (record.workshop == currentWorkshop) {
        entries.add((vehicle: vehicle, record: record));
      }
    }
  }
  return entries;
}
