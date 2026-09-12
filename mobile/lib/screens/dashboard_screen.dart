import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/mt_widgets.dart';
import 'service_detail_screen.dart';

/// Painel da Oficina — the mechanic's home (design/Dashboard.dc.html).
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final records = workshopRecords();

    return Scaffold(
      appBar: MtHomeHeader(
        subtitle: 'Bem-vindo, $currentWorkshop',
        onSignOut: () => Navigator.pushReplacementNamed(context, Routes.login),
      ),
      body: ListView(
        padding: const EdgeInsets.all(MtSizes.screenPadding),
        children: [
          _monthBanner(records.length),
          const SizedBox(height: 20),
          _searchCard(context),
          const SizedBox(height: 20),
          _newRecordCard(context),
          const SizedBox(height: 20),
          const Text(
            'Registros Recentes',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          for (final entry in records) ...[
            _recordTile(context, entry.vehicle, entry.record),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
          OutlinedButton(
            key: const Key('dashboard-cadastrar-veiculo'),
            onPressed: () =>
                Navigator.pushNamed(context, Routes.vehicleRegister),
            child: const Text('Cadastrar veículo'),
          ),
        ],
      ),
    );
  }

  Widget _monthBanner(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: MtColors.petrolTint,
        border: Border.all(color: MtColors.petrolBorder),
        borderRadius: BorderRadius.circular(MtSizes.cardRadius),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          const Flexible(
            child: Text(
              'Serviços registrados este mês',
              style: TextStyle(
                fontSize: 13,
                color: MtColors.petrol,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: MtColors.petrol,
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchCard(BuildContext context) {
    return MtCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Buscar Veículo',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text(
            'Consulte o histórico pela placa',
            style: TextStyle(fontSize: 13, color: MtColors.slate500),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: TextField(
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 15),
                  decoration: InputDecoration(hintText: 'ABC1D23'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: OutlinedButton(
                  key: const Key('dashboard-buscar'),
                  onPressed: () =>
                      Navigator.pushNamed(context, Routes.newRecord),
                  child: const Text('Buscar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _newRecordCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MtColors.petrol,
        borderRadius: BorderRadius.circular(MtSizes.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Novo Registro',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: MtColors.slate50,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Lançar um serviço realizado agora',
            style: TextStyle(fontSize: 13, color: MtColors.petrolBorder),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            key: const Key('dashboard-criar-registro'),
            onPressed: () => Navigator.pushNamed(context, Routes.newRecord),
            style: ElevatedButton.styleFrom(
              backgroundColor: MtColors.slate50,
              foregroundColor: MtColors.petrol,
              minimumSize: const Size.fromHeight(MtSizes.controlHeight),
            ),
            child: const Text('Criar Registro'),
          ),
        ],
      ),
    );
  }

  Widget _recordTile(
    BuildContext context,
    Vehicle vehicle,
    ServiceRecord record,
  ) {
    return InkWell(
      key: Key('record-${record.id}'),
      onTap: () => Navigator.pushNamed(
        context,
        Routes.serviceDetail,
        arguments: ServiceDetailArgs(vehicle: vehicle, record: record),
      ),
      borderRadius: BorderRadius.circular(MtSizes.cardRadius),
      child: MtCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        vehicle.plate,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        vehicle.label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    record.operationsLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      color: MtColors.slate500,
                    ),
                  ),
                  Text(
                    '${record.date} · ${record.mileageKm} km',
                    style: const TextStyle(
                      fontSize: 12,
                      color: MtColors.slate500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: MtColors.slate100,
                borderRadius: BorderRadius.circular(9999),
              ),
              child: Text(
                record.mechanic,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: MtColors.rust,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
