import 'package:flutter/material.dart';

import '../models/vehicle.dart';
import '../storage/garage_store.dart';
import '../theme.dart';
import '../widgets/feedback.dart';
import '../widgets/mt_widgets.dart';

typedef Claim = ({String plate, String chassiSuffix});

/// Claiming a bike: the plate plus the end of the chassi that proves it.
class ClaimDialog extends StatefulWidget {
  const ClaimDialog({super.key, this.plate});

  final String? plate;

  @override
  State<ClaimDialog> createState() => _ClaimDialogState();
}

class _ClaimDialogState extends State<ClaimDialog> {
  late final _plate = TextEditingController(text: widget.plate);
  final _chassiSuffix = TextEditingController();

  @override
  void dispose() {
    _plate.dispose();
    _chassiSuffix.dispose();
    super.dispose();
  }

  void _submit() {
    final plate = _plate.text.trim();
    final suffix = _chassiSuffix.text.trim();
    if (plate.isEmpty) return;
    if (suffix.length != chassiSuffixLength) {
      showApiError(
        context,
        'Informe os $chassiSuffixLength últimos caracteres do chassi.',
      );
      return;
    }
    Navigator.pop<Claim>(context, (plate: plate, chassiSuffix: suffix));
  }

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      title: widget.plate == null ? 'Adicionar moto' : 'Vincular à conta',
      onSubmit: _submit,
      children: [
        MtField(
          key: const Key('adicionar-moto-placa'),
          label: 'Placa',
          hint: 'ABC1D23',
          mono: true,
          controller: _plate,
          textCapitalization: TextCapitalization.characters,
        ),
        const SizedBox(height: 14),
        MtField(
          key: const Key('adicionar-moto-chassi'),
          label: 'Final do chassi',
          hint: '000001',
          helper:
              'Os $chassiSuffixLength últimos caracteres, no documento da '
              'moto (CRLV). Provam que ela é sua.',
          mono: true,
          controller: _chassiSuffix,
          textCapitalization: TextCapitalization.characters,
        ),
        const SizedBox(height: 14),
        const MtFootnote(
          'As anotações desta moto entram no histórico público da placa, '
          'que oficinas e compradores veem.',
        ),
      ],
    );
  }
}

/// Adding or editing a bike on the device: only what the rider can read off it.
class LocalBikeDialog extends StatefulWidget {
  const LocalBikeDialog({super.key, this.initial});

  final LocalBike? initial;

  @override
  State<LocalBikeDialog> createState() => _LocalBikeDialogState();
}

class _LocalBikeDialogState extends State<LocalBikeDialog> {
  late final _plate = TextEditingController(text: widget.initial?.plate);
  late final _label = TextEditingController(text: widget.initial?.label);
  late final _year = TextEditingController(
    text: widget.initial?.year?.toString(),
  );
  late final _mileage = TextEditingController(
    text: widget.initial?.mileageKm.toString(),
  );

  @override
  void dispose() {
    _plate.dispose();
    _label.dispose();
    _year.dispose();
    _mileage.dispose();
    super.dispose();
  }

  void _submit() {
    final plate = _plate.text.trim();
    final label = _label.text.trim();
    final year = int.tryParse(_year.text.trim());
    final mileage = int.tryParse(_mileage.text.trim().replaceAll('.', ''));
    final error = _validate(plate, label, year, mileage);
    if (error != null) {
      showApiError(context, error);
      return;
    }
    Navigator.pop<LocalBike>(
      context,
      LocalBike(
        id: widget.initial?.id,
        plate: plate,
        label: label,
        year: year,
        mileageKm: mileage ?? 0,
      ),
    );
  }

  String? _validate(String plate, String label, int? year, int? mileage) {
    if (!isValidPlate(plate)) return 'Placa inválida. Use ABC1234 ou ABC1D23.';
    if (label.isEmpty) return 'Informe a marca e o modelo da moto.';
    final lastYear = DateTime.now().year + 1;
    if (_year.text.trim().isNotEmpty &&
        (year == null || year < 1900 || year > lastYear)) {
      return 'Ano inválido.';
    }
    if (_mileage.text.trim().isNotEmpty && (mileage == null || mileage < 0)) {
      return 'Quilometragem inválida.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      title: widget.initial == null ? 'Adicionar moto' : 'Editar moto',
      onSubmit: _submit,
      children: [
        MtField(
          key: const Key('adicionar-moto-placa'),
          label: 'Placa',
          hint: 'ABC1D23',
          mono: true,
          controller: _plate,
          textCapitalization: TextCapitalization.characters,
        ),
        const SizedBox(height: 14),
        MtField(
          key: const Key('adicionar-moto-modelo'),
          label: 'Marca e modelo',
          hint: 'Honda CG 160 Start',
          controller: _label,
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: MtField(
                key: const Key('adicionar-moto-ano'),
                label: 'Ano',
                hint: '2022',
                controller: _year,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MtField(
                key: const Key('adicionar-moto-km'),
                label: 'Quilometragem',
                hint: '18420',
                controller: _mileage,
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const MtFootnote(
          'Sem conta, a moto fica salva neste aparelho. Reivindicar a '
          'propriedade — e receber os registros das oficinas — exige entrar.',
        ),
      ],
    );
  }
}

class _DialogFrame extends StatelessWidget {
  const _DialogFrame({
    required this.title,
    required this.onSubmit,
    required this.children,
  });

  final String title;
  final VoidCallback onSubmit;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(MtSizes.screenPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            ...children,
            const SizedBox(height: 20),
            ElevatedButton(
              key: const Key('adicionar-moto-continuar'),
              onPressed: onSubmit,
              child: const Text('Continuar'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}
