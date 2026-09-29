import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../models/service_record.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import '../widgets/feedback.dart';
import '../widgets/mt_widgets.dart';
import '../widgets/photo_image.dart';

class ServiceDetailArgs {
  const ServiceDetailArgs({required this.record, this.canRevise = false});

  /// The record carries its own vehicle summary, so the detail screen needs
  /// nothing else to render.
  final ServiceRecord record;

  /// True when the workshop that wrote the record is the one looking at it.
  /// The server enforces this too; the flag only decides whether to offer.
  final bool canRevise;
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
          if (record.supersededByRecordId case final correctionId?) ...[
            const SizedBox(height: 16),
            _supersededBanner(context, correctionId),
          ],
          const SizedBox(height: 16),
          MtCard(
            child: Column(
              children: [
                if (record.revisesRecordId != null) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Correção de um registro anterior',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: MtColors.petrol,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
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
          if (args.canRevise && record.supersededByRecordId == null) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              key: const Key('detalhe-corrigir'),
              onPressed: () => _revise(context, record),
              child: const Text('Corrigir registro'),
            ),
          ],
          const SizedBox(height: 16),
          const MtFootnote(
            'Registro imutável: correções geram uma nova revisão, '
            'preservando o histórico original.',
          ),
        ],
      ),
    );
  }

  /// Replaces this screen with the correction, so going back lands where the
  /// user started — not on the record that was just superseded. The `true`
  /// result tells the dashboard its feed changed.
  Future<void> _revise(BuildContext context, ServiceRecord record) async {
    final corrected = await Navigator.pushNamed(
      context,
      Routes.reviseRecord,
      arguments: record,
    );
    if (corrected is! ServiceRecord || !context.mounted) return;
    await Navigator.pushReplacementNamed(
      context,
      Routes.serviceDetail,
      arguments: ServiceDetailArgs(
        record: corrected,
        canRevise: args.canRevise,
      ),
      result: true,
    );
  }

  Future<void> _openCorrection(BuildContext context, String id) async {
    try {
      final correction = await AppScope.read(context).serviceRecords.byId(id);
      if (!context.mounted) return;
      await Navigator.pushReplacementNamed(
        context,
        Routes.serviceDetail,
        arguments: ServiceDetailArgs(
          record: correction,
          canRevise: args.canRevise,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      showApiError(context, error);
    }
  }

  Widget _supersededBanner(BuildContext context, String correctionId) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: MtColors.warning.withValues(alpha: 0.12),
        border: Border.all(color: MtColors.warning.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(MtSizes.controlRadius),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Este registro foi corrigido pela oficina.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          TextButton(
            key: const Key('detalhe-ver-correcao'),
            onPressed: () => _openCorrection(context, correctionId),
            child: const Text('Ver correção'),
          ),
        ],
      ),
    );
  }

  Future<void> _openInvoice(BuildContext context, Attachment invoice) async {
    // A demo upload only exists in memory, so it is shown, not opened.
    if (isDemoPhoto(invoice.url)) {
      await showDialog<void>(
        context: context,
        builder: (_) => _Gallery(label: 'Nota fiscal', attachments: [invoice]),
      );
      return;
    }

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

/// One phase's photos: the first as a thumbnail, all of them in a gallery
/// on tap.
class _Photo extends StatelessWidget {
  const _Photo({required this.label, this.attachments = const []});

  final String label;
  final List<Attachment> attachments;

  @override
  Widget build(BuildContext context) {
    final photo = attachments.firstOrNull;

    return Column(
      children: [
        InkWell(
          key: Key('detalhe-fotos-$label'),
          onTap: photo == null
              ? null
              : () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      _Gallery(label: label, attachments: attachments),
                ),
          borderRadius: BorderRadius.circular(MtSizes.controlRadius),
          child: Container(
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
                : _NetworkPhoto(url: photo.url, fit: BoxFit.cover),
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

class _Gallery extends StatefulWidget {
  const _Gallery({required this.label, required this.attachments});

  final String label;
  final List<Attachment> attachments;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  var _page = 0;

  @override
  Widget build(BuildContext context) {
    final count = widget.attachments.length;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    count > 1
                        ? '${widget.label} · ${_page + 1} de $count'
                        : widget.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 360,
            child: PageView(
              onPageChanged: (page) => setState(() => _page = page),
              children: [
                for (final attachment in widget.attachments)
                  ColoredBox(
                    color: MtColors.slate100,
                    child: _NetworkPhoto(
                      url: attachment.url,
                      fit: BoxFit.contain,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NetworkPhoto extends StatelessWidget {
  const _NetworkPhoto({required this.url, required this.fit});

  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: photoImage(url),
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      // A broken URL must not take the whole record down.
      errorBuilder: (_, _, _) => const Icon(
        Icons.broken_image_outlined,
        color: Color(0xFF94A3B8),
        size: 26,
      ),
    );
  }
}
