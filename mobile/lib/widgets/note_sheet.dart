import 'package:flutter/material.dart';

import '../models/service_record.dart';
import '../theme.dart';
import 'mt_widgets.dart';

/// An owner's maintenance note in full, with its photo. [onDelete] adds the
/// delete button, for the rider's own notes.
Future<void> showNoteSheet(
  BuildContext context, {
  required String description,
  required DateTime doneOn,
  int? mileageKm,
  int? costCents,
  ImageProvider? photo,
  String badge = 'Informado pelo dono',
  VoidCallback? onDelete,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          MtSizes.screenPadding,
          0,
          MtSizes.screenPadding,
          MtSizes.screenPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: MtBadge.ownerNote(label: badge),
            ),
            const SizedBox(height: 10),
            Text(
              description,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            MtDetailRow(label: 'Data', value: formatDate(doneOn)),
            if (mileageKm != null)
              MtDetailRow(label: 'Quilometragem', value: '$mileageKm km'),
            if (costCents != null)
              MtDetailRow(label: 'Valor', value: formatCents(costCents)),
            if (photo != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(MtSizes.controlRadius),
                child: ColoredBox(
                  color: MtColors.slate100,
                  child: Image(
                    key: const Key('anotacao-foto'),
                    image: photo,
                    height: 240,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const SizedBox(
                      height: 80,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: MtColors.slate500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            const MtFootnote(
              'Escrito pelo dono da moto. Nenhuma oficina confirmou este serviço.',
            ),
            if (onDelete != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                key: const Key('anotacao-apagar'),
                onPressed: () {
                  Navigator.pop(context);
                  onDelete();
                },
                style: TextButton.styleFrom(
                  foregroundColor: MtColors.dangerText,
                ),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Apagar anotação'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
