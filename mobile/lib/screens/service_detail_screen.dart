import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../theme.dart';
import '../widgets/mt_widgets.dart';

class ServiceDetailArgs {
  const ServiceDetailArgs({required this.vehicle, required this.record});

  final Vehicle vehicle;
  final ServiceRecord record;
}

/// Detalhe do Serviço — one immutable record with parts, photos and invoice.
class ServiceDetailScreen extends StatelessWidget {
  const ServiceDetailScreen({super.key, required this.args});

  final ServiceDetailArgs args;

  @override
  Widget build(BuildContext context) {
    final record = args.record;
    final vehicle = args.vehicle;

    return Scaffold(
      appBar: AppBar(title: const Text('Detalhe do Serviço')),
      body: ListView(
        padding: const EdgeInsets.all(MtSizes.screenPadding),
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
                vehicle.labelWithYear,
                style: const TextStyle(fontSize: 13, color: MtColors.slate500),
              ),
            ],
          ),
          const SizedBox(height: 16),
          MtCard(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < record.operations.length; i++)
                        MtChip(label: record.operations[i], selected: i == 0),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                MtDetailRow(label: 'Data', value: record.date),
                MtDetailRow(label: 'Oficina', value: record.workshop),
                MtDetailRow(label: 'Mecânico', value: record.mechanic),
                MtDetailRow(
                  label: 'Quilometragem',
                  value: '${record.mileageKm} km',
                  mono: true,
                ),
                MtDetailRow(
                  label: 'Valor total',
                  value:
                      'R\$ ${record.cost.toStringAsFixed(2).replaceAll('.', ',')}',
                  mono: true,
                ),
              ],
            ),
          ),
          if (record.parts.isNotEmpty) ...[
            const SizedBox(height: 16),
            MtCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Peças utilizadas',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  for (final part in record.parts)
                    MtDetailRow(
                      label: '${part.name} · ${part.quantity}',
                      value:
                          'R\$ ${part.cost.toStringAsFixed(2).replaceAll('.', ',')}',
                      mono: true,
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          MtCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Observações',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  record.notes,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          MtCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Fotos do serviço',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Row(
                  children: const [
                    Expanded(child: _Photo(label: 'Antes')),
                    SizedBox(width: 10),
                    Expanded(child: _Photo(label: 'Depois')),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: MtColors.slate200),
                    borderRadius: BorderRadius.circular(MtSizes.controlRadius),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: const [
                          Icon(
                            Icons.description_outlined,
                            size: 18,
                            color: MtColors.petrol,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Nota fiscal',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const Text(
                        'Baixar',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: MtColors.rust,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const MtFootnote(
            'Registro imutável: correções geram uma nova revisão, '
            'preservando o histórico original.',
          ),
        ],
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 100,
          decoration: BoxDecoration(
            color: MtColors.slate100,
            border: Border.all(color: MtColors.slate200),
            borderRadius: BorderRadius.circular(MtSizes.controlRadius),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.image_outlined,
            color: Color(0xFF94A3B8),
            size: 26,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: MtColors.slate500),
        ),
      ],
    );
  }
}
