import 'package:flutter/material.dart';

import '../models/owner.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import '../widgets/feedback.dart';
import '../widgets/mt_widgets.dart';

/// Lembretes — km-based maintenance reminders (ARCHITECTURE.md §3).
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  bool _whatsapp = true;
  Future<List<OwnedVehicle>>? _vehicles;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _vehicles ??= AppScope.read(context).owners.myVehicles();
  }

  Future<void> _reload() async {
    final reloaded = AppScope.read(context).owners.myVehicles();
    setState(() {
      _vehicles = reloaded;
    });
    await reloaded;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lembretes')),
      body: FutureBuilder<List<OwnedVehicle>>(
        future: _vehicles,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const MtLoading();
          }
          if (snapshot.hasError) {
            return MtEmptyState(
              message: 'Não foi possível carregar os lembretes.',
              icon: Icons.cloud_off_outlined,
              onRetry: _reload,
            );
          }
          return _body(snapshot.data ?? const []);
        },
      ),
    );
  }

  Widget _body(List<OwnedVehicle> vehicles) {
    final due = vehicles.where((v) => v.reminderIsDue).length;

    return ListView(
      padding: const EdgeInsets.all(MtSizes.screenPadding),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: MtColors.warning.withValues(alpha: 0.12),
            border: Border.all(color: MtColors.warning.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(MtSizes.cardRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                due == 1 ? '1 manutenção próxima' : '$due manutenções próximas',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: MtColors.warningText,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Avisos enviados por WhatsApp, por km rodado ou tempo decorrido.',
                style: TextStyle(
                  fontSize: 12,
                  color: MtColors.warningText,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (vehicles.isEmpty)
          const MtEmptyState(
            message: 'Cadastre uma moto para receber lembretes.',
            icon: Icons.notifications_none,
          ),
        for (final vehicle in vehicles) ...[
          _reminderCard(vehicle),
          const SizedBox(height: 14),
        ],
        MtCard(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Avisos por WhatsApp',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Receber lembretes no celular cadastrado',
                      style: TextStyle(fontSize: 12, color: MtColors.slate500),
                    ),
                  ],
                ),
              ),
              Switch(
                key: const Key('lembretes-whatsapp'),
                value: _whatsapp,
                activeThumbColor: Colors.white,
                activeTrackColor: MtColors.petrol,
                onChanged: (value) => setState(() => _whatsapp = value),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reminderCard(OwnedVehicle vehicle) {
    final km = vehicle.kmUntilDue;
    return _ReminderCard(
      title: 'Troca de óleo e filtro',
      vehicle: '${vehicle.plate} · ${vehicle.label}',
      status: vehicle.reminderIsDue ? 'Em breve' : 'Em dia',
      due: vehicle.reminderIsDue,
      progress: vehicle.scheduleProgress,
      left: switch (vehicle) {
        _ when !vehicle.hasSchedule => 'sem previsão',
        _ when km < 0 => 'atrasada em ${-km} km',
        _ => 'faltam $km km',
      },
      elapsed: '${vehicle.currentMileageKm} km rodados',
      footer: vehicle.hasSchedule
          ? 'Próxima troca aos ${vehicle.nextOilChangeKm} km · '
                'a cada ${vehicle.oilChangeIntervalKm} km'
          : 'Nenhuma troca de óleo registrada ainda',
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.title,
    required this.vehicle,
    required this.status,
    required this.due,
    required this.progress,
    required this.left,
    required this.elapsed,
    required this.footer,
  });

  final String title;
  final String vehicle;
  final String status;
  final bool due;
  final double progress;
  final String left;
  final String elapsed;
  final String footer;

  @override
  Widget build(BuildContext context) {
    final accent = due ? MtColors.warning : MtColors.success;
    final accentText = due ? MtColors.warningText : MtColors.successText;

    return MtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      vehicle,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: accentText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(9999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: MtColors.slate100,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  elapsed,
                  style: const TextStyle(
                    fontSize: 11,
                    color: MtColors.slate500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                left,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: due ? FontWeight.w600 : FontWeight.w400,
                  color: due ? accentText : MtColors.slate500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            footer,
            style: const TextStyle(fontSize: 11, color: MtColors.slate500),
          ),
        ],
      ),
    );
  }
}
