/// Sample data for the **proprietário** side only.
///
/// The oficina flow and the public plate lookup talk to the real Go API. Owner
/// sign-in is phone+OTP, which needs an SMS/WhatsApp sender the backend does
/// not have yet, so Minhas Motos and Lembretes still render these fixtures.
/// They use the same model types as the API responses, so wiring them up later
/// is a swap of the data source, not of the screens.
library;

import '../models/service_operation.dart';
import '../models/service_record.dart';
import '../models/vehicle.dart';

/// A bike as the owner sees it: the vehicle, its history, and where it stands
/// against the next scheduled maintenance.
class OwnerVehicle {
  const OwnerVehicle({
    required this.vehicle,
    required this.currentMileageKm,
    required this.color,
    required this.history,
    this.reminder,
    this.reminderIsDue = false,
  });

  final VehicleSummary vehicle;
  final int currentMileageKm;
  final String color;
  final List<ServiceRecord> history;

  /// Short status for the card, or null when nothing is due.
  final String? reminder;
  final bool reminderIsDue;

  String get plate => vehicle.plate;
  String get label => vehicle.label;
  int get year => vehicle.year;
}

const _cg160 = VehicleSummary(
  plate: 'ABC1D23',
  make: 'Honda',
  model: 'CG 160 Start',
  year: 2022,
);

const _fazer = VehicleSummary(
  plate: 'BRA2E19',
  make: 'Yamaha',
  model: 'Fazer 250',
  year: 2021,
);

final _cg160History = <ServiceRecord>[
  ServiceRecord(
    id: 'r1',
    vehicle: _cg160,
    workshopName: 'Oficina do Zé',
    mechanicName: 'José Carlos',
    operations: const [
      ServiceOperation.oilChange,
      ServiceOperation.chainAndSprocket,
    ],
    mileageKm: 18420,
    costCents: 24500,
    notes: 'Óleo 10w30 semissintético trocado, corrente limpa e lubrificada. '
        'Recomendada revisão da suspensão na próxima visita.',
    parts: const [
      Part(name: 'Óleo 10w30 semissintético', quantity: 1, costCents: 6200),
      Part(name: 'Filtro de óleo', quantity: 1, costCents: 3800),
      Part(name: 'Kit relação', quantity: 1, costCents: 14500),
    ],
    createdAt: DateTime.utc(2026, 6, 2),
  ),
  ServiceRecord(
    id: 'r2',
    vehicle: _cg160,
    workshopName: 'Moto Center Silva',
    mechanicName: 'Carlos Silva',
    operations: const [ServiceOperation.brakes],
    mileageKm: 16100,
    costCents: 18000,
    notes: 'Pastilhas dianteira e traseira substituídas, fluido de freio verificado.',
    createdAt: DateTime.utc(2026, 2, 14),
  ),
  ServiceRecord(
    id: 'r3',
    vehicle: _cg160,
    workshopName: 'Oficina do Zé',
    mechanicName: 'José Carlos',
    operations: const [ServiceOperation.scheduledReview],
    mileageKm: 13500,
    costCents: 15000,
    notes: 'Revisão programada dos 13 mil km, nenhuma pendência encontrada.',
    createdAt: DateTime.utc(2025, 9, 30),
  ),
];

final _fazerHistory = <ServiceRecord>[
  ServiceRecord(
    id: 'r4',
    vehicle: _fazer,
    workshopName: 'Oficina do Zé',
    mechanicName: 'José Carlos',
    operations: const [ServiceOperation.tires, ServiceOperation.suspension],
    mileageKm: 32180,
    costCents: 62000,
    notes: 'Par de pneus trocado, suspensão dianteira regulada.',
    createdAt: DateTime.utc(2026, 5, 28),
  ),
  ServiceRecord(
    id: 'r5',
    vehicle: _fazer,
    workshopName: 'Auto Peças e Motos Ipiranga',
    mechanicName: 'Roberto Nunes',
    operations: const [ServiceOperation.sparkPlugs, ServiceOperation.electrical],
    mileageKm: 29800,
    costCents: 21000,
    notes: 'Velas trocadas, bateria testada e recarregada.',
    createdAt: DateTime.utc(2026, 1, 11),
  ),
];

final mockOwnerVehicles = <OwnerVehicle>[
  OwnerVehicle(
    vehicle: _cg160,
    currentMileageKm: 18420,
    color: 'Vermelha',
    history: _cg160History,
    reminder: 'Troca de óleo em 580 km',
    reminderIsDue: true,
  ),
  OwnerVehicle(
    vehicle: _fazer,
    currentMileageKm: 32180,
    color: 'Preta',
    history: _fazerHistory,
    reminder: 'Em dia',
  ),
];
