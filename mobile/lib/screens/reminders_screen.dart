import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/mt_widgets.dart';

/// Lembretes — km/time based maintenance reminders (ARCHITECTURE.md §3).
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  bool _whatsapp = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lembretes')),
      body: ListView(
        padding: const EdgeInsets.all(MtSizes.screenPadding),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: MtColors.warning.withValues(alpha: 0.12),
              border: Border.all(
                color: MtColors.warning.withValues(alpha: 0.4),
              ),
              borderRadius: BorderRadius.circular(MtSizes.cardRadius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  '1 manutenção próxima',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: MtColors.warningText,
                  ),
                ),
                SizedBox(height: 2),
                Text(
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
          const _ReminderCard(
            title: 'Troca de óleo e filtro',
            vehicle: 'ABC1D23 · Honda CG 160 Start',
            status: 'Em breve',
            due: true,
            progress: 0.81,
            left: 'faltam 580 km',
            elapsed: '18.420 km rodados',
            footer: 'Última troca: 02/06/2026 · a cada 3.000 km',
          ),
          const SizedBox(height: 14),
          const _ReminderCard(
            title: 'Revisão programada',
            vehicle: 'BRA2E19 · Yamaha Fazer 250',
            status: 'Em dia',
            due: false,
            progress: 0.34,
            left: 'vence em 8 meses',
            elapsed: '4 meses desde a última',
            footer: 'Última revisão: 28/05/2026 · a cada 12 meses',
          ),
          const SizedBox(height: 14),
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
                        'Receber lembretes no (31) 9****-0000',
                        style: TextStyle(
                          fontSize: 12,
                          color: MtColors.slate500,
                        ),
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
      ),
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
