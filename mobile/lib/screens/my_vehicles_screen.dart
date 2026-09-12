import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/mt_widgets.dart';
import 'service_detail_screen.dart';

/// Minhas Motos — the owner's home screen.
class MyVehiclesScreen extends StatelessWidget {
  const MyVehiclesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MtHomeHeader(
        subtitle: 'Olá, Marcos Vinícius',
        onSignOut: () => Navigator.pushReplacementNamed(context, Routes.login),
      ),
      body: ListView(
        padding: const EdgeInsets.all(MtSizes.screenPadding),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Minhas Motos',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              Text(
                '${mockOwnerVehicles.length} veículos',
                style: const TextStyle(fontSize: 12, color: MtColors.slate500),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final vehicle in mockOwnerVehicles) ...[
            _vehicleTile(context, vehicle),
            const SizedBox(height: 16),
          ],
          ElevatedButton(
            key: const Key('minhas-motos-cadastrar'),
            onPressed: () =>
                Navigator.pushNamed(context, Routes.vehicleRegister),
            child: const Text('+ Cadastrar nova moto'),
          ),
          const SizedBox(height: 16),
          InkWell(
            key: const Key('minhas-motos-lembretes'),
            onTap: () => Navigator.pushNamed(context, Routes.reminders),
            borderRadius: BorderRadius.circular(MtSizes.cardRadius),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: MtColors.petrolTint,
                border: Border.all(color: MtColors.petrolBorder),
                borderRadius: BorderRadius.circular(MtSizes.cardRadius),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lembretes de manutenção',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: MtColors.petrol,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '1 manutenção próxima',
                          style: TextStyle(
                            fontSize: 12,
                            color: MtColors.petrol,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: MtColors.petrol, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vehicleTile(BuildContext context, OwnerVehicle vehicle) {
    final due = vehicle.reminderIsDue;

    return InkWell(
      key: Key('vehicle-${vehicle.plate}'),
      onTap: () => Navigator.pushNamed(
        context,
        Routes.serviceDetail,
        arguments: ServiceDetailArgs(record: vehicle.history.first),
      ),
      borderRadius: BorderRadius.circular(MtSizes.cardRadius),
      child: MtCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
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
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        vehicle.label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${vehicle.year} · ${vehicle.color} · ${vehicle.currentMileageKm} km',
                    style: const TextStyle(
                      fontSize: 12,
                      color: MtColors.slate500,
                    ),
                  ),
                  if (vehicle.reminder != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: (due ? MtColors.warning : MtColors.success)
                            .withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      child: Text(
                        vehicle.reminder!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: due
                              ? MtColors.warningText
                              : MtColors.successText,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: MtColors.slate500, size: 18),
          ],
        ),
      ),
    );
  }
}
