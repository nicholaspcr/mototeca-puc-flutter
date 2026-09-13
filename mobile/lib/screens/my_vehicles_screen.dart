import 'package:flutter/material.dart';

import '../main.dart';
import '../models/owner.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import '../widgets/feedback.dart';
import '../widgets/mt_widgets.dart';
import 'service_detail_screen.dart';

/// Minhas Motos — the owner's home screen.
class MyVehiclesScreen extends StatefulWidget {
  const MyVehiclesScreen({super.key});

  @override
  State<MyVehiclesScreen> createState() => _MyVehiclesScreenState();
}

class _MyVehiclesScreenState extends State<MyVehiclesScreen> {
  Future<List<OwnedVehicle>>? _vehicles;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Kicked off here rather than initState because it needs AppScope.
    _vehicles ??= AppScope.read(context).owners.myVehicles();
  }

  Future<void> _reload() async {
    final reloaded = AppScope.read(context).owners.myVehicles();
    setState(() {
      _vehicles = reloaded;
    });
    // The FutureBuilder renders the failure; awaiting it here too would make
    // the same error unhandled a second time.
    try {
      await reloaded;
    } on Object {
      // handled above
    }
  }

  void _signOut() {
    AppScope.read(context).signOut();
    Navigator.pushReplacementNamed(context, Routes.login);
  }

  /// Register then claim: a vehicle exists independently of any owner, which
  /// is what lets its history survive a sale.
  Future<void> _addVehicle() async {
    final created = await Navigator.pushNamed(context, Routes.vehicleRegister);
    if (created is! String || !mounted) return;

    try {
      await AppScope.read(context).owners.claimVehicle(created);
      if (!mounted) return;
      await _reload();
    } catch (error) {
      if (!mounted) return;
      showApiError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = AppScope.of(context).owner;

    return Scaffold(
      appBar: MtHomeHeader(
        subtitle: 'Olá, ${owner?.name ?? 'proprietário'}',
        onSignOut: _signOut,
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<OwnedVehicle>>(
          future: _vehicles,
          builder: (context, snapshot) => _body(context, snapshot),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AsyncSnapshot<List<OwnedVehicle>> snapshot,
  ) {
    final vehicles = snapshot.data ?? const <OwnedVehicle>[];
    final dueCount = vehicles.where((v) => v.reminderIsDue).length;

    return ListView(
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
              snapshot.hasData
                  ? '${vehicles.length} ${vehicles.length == 1 ? 'veículo' : 'veículos'}'
                  : '',
              style: const TextStyle(fontSize: 12, color: MtColors.slate500),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (snapshot.connectionState == ConnectionState.waiting)
          const MtLoading()
        else if (snapshot.hasError)
          MtEmptyState(
            message: 'Não foi possível carregar suas motos.',
            icon: Icons.cloud_off_outlined,
            onRetry: _reload,
          )
        else if (vehicles.isEmpty)
          const MtEmptyState(
            message:
                'Você ainda não tem motos vinculadas.\n'
                'Cadastre a primeira pela placa.',
            icon: Icons.two_wheeler_outlined,
          ),
        for (final vehicle in vehicles) ...[
          _vehicleTile(context, vehicle),
          const SizedBox(height: 16),
        ],
        ElevatedButton(
          key: const Key('minhas-motos-cadastrar'),
          onPressed: _addVehicle,
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
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Lembretes de manutenção',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: MtColors.petrol,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dueCount == 1
                            ? '1 manutenção próxima'
                            : '$dueCount manutenções próximas',
                        style: const TextStyle(
                          fontSize: 12,
                          color: MtColors.petrol,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: MtColors.petrol,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _vehicleTile(BuildContext context, OwnedVehicle vehicle) {
    final due = vehicle.reminderIsDue;

    return InkWell(
      key: Key('vehicle-${vehicle.plate}'),
      // A bike with no service yet has no detail screen to open.
      onTap: vehicle.lastService == null
          ? null
          : () => Navigator.pushNamed(
              context,
              Routes.serviceDetail,
              arguments: ServiceDetailArgs(record: vehicle.lastService!),
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
                    '${vehicle.year} · ${vehicle.currentMileageKm} km · '
                    '${vehicle.serviceCount} ${vehicle.serviceCount == 1 ? 'serviço' : 'serviços'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: MtColors.slate500,
                    ),
                  ),
                  if (vehicle.reminder.isNotEmpty) ...[
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
                        vehicle.reminder,
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
