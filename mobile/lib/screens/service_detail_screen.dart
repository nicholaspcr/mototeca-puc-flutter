import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/service_record.dart';
import '../theme.dart';
import '../widgets/feedback.dart';
import '../widgets/mt_widgets.dart';

class ServiceDetailArgs {
  const ServiceDetailArgs({required this.record});

  /// The record carries its own vehicle summary, so the detail screen needs
  /// nothing else to render.
  final ServiceRecord record;
}

/// Detalhe do Serviço — one immutable record with parts, photos and invoice.
class ServiceDetailScreen extends StatelessWidget {
  const ServiceDetailScreen({super.key, required this.args});

  final ServiceDetailArgs args;

  @override
  Widget build(BuildContext context) {
    final record = args.record;
    final vehicle = record.vehicle;

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
                      // Every operation in the record carries the same weight,
                      // so they all read as the same read-only tag.
                      for (final operation in record.operations)
                        MtChip.tag(label: operation.label),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                MtDetailRow(label: 'Data', value: record.formattedDate),
                MtDetailRow(label: 'Oficina', value: record.workshopName),
                if (record.mechanicName != null)
                  MtDetailRow(label: 'Mecânico', value: record.mechanicName!),
                MtDetailRow(
                  label: 'Quilometragem',
                  value: '${record.mileageKm} km',
                  mono: true,
                ),
                MtDetailRow(
                  label: 'Valor total',
                  value: record.formattedCost,
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
                      value: part.costCents == null
                          ? '—'
                          : formatCents(part.costCents!),
                      mono: true,
                    ),
                ],
              ),
            ),
          ],
          if (record.notes != null && record.notes!.isNotEmpty) ...[
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
                    record.notes!,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _photosCard(context, record),
          const SizedBox(height: 16),
          const MtFootnote(
            'Registro imutável: correções geram uma nova revisão, '
            'preservando o histórico original.',
          ),
        ],
      ),
    );
  }

  Future<void> _openInvoice(BuildContext context, Attachment invoice) async {
    final opened = await launchUrl(
      Uri.parse(invoice.url),
      mode: LaunchMode.externalApplication,
    ).catchError((Object _) => false);
    if (!opened && context.mounted) {
      showApiError(context, 'Não foi possível abrir a nota fiscal.');
    }
  }

  Widget _photosCard(BuildContext context, ServiceRecord record) {
    final before = record.attachments
        .where((a) => a.phase == 'PHOTO_PHASE_BEFORE')
        .toList();
    final after = record.attachments
        .where((a) => a.phase == 'PHOTO_PHASE_AFTER')
        .toList();
    final invoice = record.attachments.where((a) => a.isInvoice).firstOrNull;

    return MtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fotos do serviço',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Photo(label: 'Antes', attachments: before),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Photo(label: 'Depois', attachments: after),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            key: const Key('detalhe-nota-fiscal'),
            onTap: invoice == null
                ? null
                : () => _openInvoice(context, invoice),
            borderRadius: BorderRadius.circular(MtSizes.controlRadius),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: MtColors.slate200),
                borderRadius: BorderRadius.circular(MtSizes.controlRadius),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Flexible(
                    child: Row(
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 18,
                          color: MtColors.petrol,
                        ),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Nota fiscal',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    invoice == null ? 'Não anexada' : 'Baixar',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: invoice == null
                          ? MtColors.slate500
                          : MtColors.rust,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One phase's photo: the first image when the record has one, a placeholder
/// otherwise.
class _Photo extends StatelessWidget {
  const _Photo({required this.label, this.attachments = const []});

  final String label;
  final List<Attachment> attachments;

  @override
  Widget build(BuildContext context) {
    final photo = attachments.firstOrNull;

    return Column(
      children: [
        Container(
          height: 100,
          decoration: BoxDecoration(
            color: MtColors.slate100,
            border: Border.all(color: MtColors.slate200),
            borderRadius: BorderRadius.circular(MtSizes.controlRadius),
          ),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          child: photo == null
              ? const Icon(
                  Icons.image_outlined,
                  color: Color(0xFF94A3B8),
                  size: 26,
                )
              : Image.network(
                  photo.url,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 100,
                  // A broken URL must not take the whole record down.
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    color: Color(0xFF94A3B8),
                    size: 26,
                  ),
                ),
        ),
        const SizedBox(height: 5),
        Text(
          attachments.length > 1 ? '$label (${attachments.length})' : label,
          style: const TextStyle(fontSize: 11, color: MtColors.slate500),
        ),
      ],
    );
  }
}
