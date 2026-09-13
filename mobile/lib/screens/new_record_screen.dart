import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_exception.dart';
import '../main.dart';
import '../models/service_operation.dart';
import '../models/service_record.dart';
import '../models/vehicle.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import '../widgets/feedback.dart';
import '../widgets/mt_widgets.dart';

/// A photo chosen but not yet uploaded. Bytes are held in memory because the
/// upload only happens once the record exists to attach them to.
class _PickedPhoto {
  const _PickedPhoto({
    required this.bytes,
    required this.name,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String name;
  final String mimeType;
}

/// One editable row in the parts list.
class _PartDraft {
  _PartDraft()
    : name = TextEditingController(),
      quantity = TextEditingController(text: '1'),
      cost = TextEditingController();

  final TextEditingController name;
  final TextEditingController quantity;
  final TextEditingController cost;

  bool get isBlank => name.text.trim().isEmpty;

  void dispose() {
    name.dispose();
    quantity.dispose();
    cost.dispose();
  }
}

/// Novo Registro — the app's main action (design/NewRecord.dc.html).
class NewRecordScreen extends StatefulWidget {
  const NewRecordScreen({super.key, this.initialPlate});

  /// Pre-filled when the mechanic arrives from the dashboard search box.
  final String? initialPlate;

  @override
  State<NewRecordScreen> createState() => _NewRecordScreenState();
}

class _NewRecordScreenState extends State<NewRecordScreen> {
  late final _plate = TextEditingController(text: widget.initialPlate ?? '');
  final _mechanic = TextEditingController();
  final _mileage = TextEditingController();
  final _cost = TextEditingController();
  final _notes = TextEditingController();
  final _parts = <_PartDraft>[_PartDraft()];
  final _selectedOps = <ServiceOperation>{};

  final _picker = ImagePicker();
  final _photos = <String, _PickedPhoto>{};
  _PickedPhoto? _invoice;

  Vehicle? _vehicle;
  bool _searched = false;
  bool _searching = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if ((widget.initialPlate ?? '').trim().isNotEmpty) {
      // Arriving with a plate already typed means the search was the intent.
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _plate.dispose();
    _mechanic.dispose();
    _mileage.dispose();
    _cost.dispose();
    _notes.dispose();
    for (final part in _parts) {
      part.dispose();
    }
    super.dispose();
  }

  Future<void> _search() async {
    if (_plate.text.trim().isEmpty) return;

    setState(() => _searching = true);
    try {
      final vehicle = await AppScope.read(context).vehicles
          .findByPlate(_plate.text);
      if (!mounted) return;
      setState(() {
        _vehicle = vehicle;
        _searched = true;
      });
    } catch (error) {
      if (!mounted) return;
      showApiError(context, error);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _save() async {
    final vehicle = _vehicle;
    if (vehicle == null) return;

    if (_selectedOps.isEmpty) {
      showApiError(context, 'Selecione ao menos uma operação.');
      return;
    }

    final int mileage;
    final int? costCents;
    final List<Part> parts;
    try {
      mileage = int.parse(_mileage.text.trim());
      costCents = parseCents(_cost.text);
      parts = _collectParts();
    } on FormatException {
      showApiError(context, 'Confira a quilometragem, o valor e as peças.');
      return;
    }

    setState(() => _saving = true);
    try {
      final repository = AppScope.read(context).serviceRecords;
      Future<ServiceRecord> create({bool confirmLowerMileage = false}) =>
          repository.create(
            plate: vehicle.plate,
            operations: _selectedOps.toList(),
            mileageKm: mileage,
            mechanicName: _mechanic.text,
            costCents: costCents,
            notes: _notes.text,
            parts: parts,
            confirmLowerMileage: confirmLowerMileage,
          );

      ServiceRecord record;
      try {
        record = await create();
      } on ApiException catch (error) {
        if (error.code != ApiErrorCode.failedPrecondition || !mounted) rethrow;
        // No spinner behind the question: nothing is saving while it waits.
        setState(() => _saving = false);
        if (!await _confirmLowerMileage(error.message) || !mounted) return;
        setState(() => _saving = true);
        record = await create(confirmLowerMileage: true);
      }
      if (!mounted) return;
      // Attachments need the record to exist, so they follow the save. A
      // failed photo must not discard a saved record — the record is the part
      // that matters.
      final failed = await _uploadAttachments(record.id);
      if (!mounted) return;
      showSuccess(
        context,
        failed == 0
            ? 'Registro salvo no histórico da moto.'
            : 'Registro salvo, mas $failed arquivo(s) não subiram.',
      );
      // true tells the dashboard its feed is stale.
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      showApiError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// A lower odometer than before is how a rolled-back bike looks, so the
  /// mechanic confirms it is real before it enters the history.
  Future<bool> _confirmLowerMileage(String message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quilometragem menor'),
        content: Text(
          '${message[0].toUpperCase()}${message.substring(1)}. '
          'Salve assim só se o painel foi trocado ou zerado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Corrigir'),
          ),
          TextButton(
            key: const Key('novo-registro-confirmar-km'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salvar assim'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// Returns how many uploads failed.
  Future<int> _uploadAttachments(String recordId) async {
    final repository = AppScope.read(context).serviceRecords;
    final uploads = [
      for (final MapEntry(key: phase, value: photo) in _photos.entries)
        (file: photo, kind: 'photo', phase: phase),
      if (_invoice case final invoice?)
        (file: invoice, kind: 'invoice', phase: null),
    ];

    var failed = 0;
    for (final upload in uploads) {
      try {
        await repository.uploadAttachment(
          recordId: recordId,
          bytes: upload.file.bytes,
          filename: upload.file.name,
          contentType: upload.file.mimeType,
          kind: upload.kind,
          phase: upload.phase,
        );
      } on Object {
        failed++;
      }
    }
    return failed;
  }

  Future<_PickedPhoto?> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      // Shop connections are poor and the API caps uploads at 8 MiB
      // (ARCHITECTURE.md §9).
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (picked == null) return null;

    return _PickedPhoto(
      bytes: await picked.readAsBytes(),
      name: picked.name,
      mimeType: picked.mimeType ?? 'image/jpeg',
    );
  }

  Future<void> _pickPhoto(String phase) async {
    final photo = await _pickImage();
    if (photo == null || !mounted) return;
    setState(() => _photos[phase] = photo);
  }

  Future<void> _pickInvoice() async {
    final invoice = await _pickImage();
    if (invoice == null || !mounted) return;
    setState(() => _invoice = invoice);
  }

  /// Blank rows are the user leaving the last row untouched, not an error.
  List<Part> _collectParts() => [
    for (final draft in _parts)
      if (!draft.isBlank)
        Part(
          name: draft.name.text.trim(),
          quantity: int.parse(draft.quantity.text.trim()),
          costCents: parseCents(draft.cost.text),
        ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Novo Registro')),
      body: ListView(
        padding: const EdgeInsets.all(MtSizes.screenPadding),
        children: [
          _vehicleCard(),
          if (_vehicle != null) ...[
            const SizedBox(height: 16),
            _operationsCard(),
            const SizedBox(height: 16),
            _detailsCard(),
            const SizedBox(height: 16),
            ElevatedButton(
              key: const Key('novo-registro-salvar'),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Salvar Registro'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _vehicleCard() {
    return MtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Veículo',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _plate,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
                  decoration: const InputDecoration(hintText: 'ABC1D23'),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: OutlinedButton(
                  key: const Key('novo-registro-buscar'),
                  onPressed: _searching ? null : _search,
                  child: _searching
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Buscar'),
                ),
              ),
            ],
          ),
          if (_searched && _vehicle == null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: MtColors.warning.withValues(alpha: 0.12),
                border: Border.all(
                  color: MtColors.warning.withValues(alpha: 0.4),
                ),
                borderRadius: BorderRadius.circular(MtSizes.controlRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nenhuma moto cadastrada com a placa '
                    '${normalizePlate(_plate.text)}. Cadastre o veículo antes '
                    'de lançar o serviço.',
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    key: const Key('novo-registro-cadastrar-veiculo'),
                    onPressed: () async {
                      final created = await Navigator.pushNamed(
                        context,
                        Routes.vehicleRegister,
                        arguments: normalizePlate(_plate.text),
                      );
                      if (created is Vehicle && mounted) {
                        _plate.text = created.plate;
                        await _search();
                      }
                    },
                    child: const Text('Cadastrar veículo'),
                  ),
                ],
              ),
            ),
          ],
          if (_vehicle != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: MtColors.slate100,
                borderRadius: BorderRadius.circular(MtSizes.controlRadius),
              ),
              child: Text(
                '${_vehicle!.labelWithYear} · ${_vehicle!.plate}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _operationsCard() {
    return MtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Operação Realizada',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final op in ServiceOperation.values)
                MtChip(
                  label: op.label,
                  selected: _selectedOps.contains(op),
                  onTap: () => setState(() {
                    if (!_selectedOps.remove(op)) _selectedOps.add(op);
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailsCard() {
    return MtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Detalhes',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: MtField(
                  key: const Key('novo-registro-km'),
                  label: 'Km atual',
                  hint: '18500',
                  controller: _mileage,
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MtField(
                  label: 'Valor (R\$)',
                  hint: '245,00',
                  controller: _cost,
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          MtField(
            label: 'Mecânico',
            hint: 'Quem executou o serviço',
            controller: _mechanic,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 16),
          const Text(
            'Peças utilizadas',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          for (final (index, part) in _parts.indexed) ...[
            _partRow(index, part),
            const SizedBox(height: 8),
          ],
          OutlinedButton(
            key: const Key('novo-registro-adicionar-peca'),
            onPressed: () => setState(() => _parts.add(_PartDraft())),
            child: const Text('+ Adicionar peça'),
          ),
          const SizedBox(height: 16),
          MtField(
            label: 'Observações',
            hint: 'Detalhes do serviço, recomendações para a próxima visita...',
            controller: _notes,
          ),
          const SizedBox(height: 16),
          const Text(
            'Fotos (antes/depois)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _PhotoSlot(
                  label: 'Foto antes',
                  photo: _photos['before'],
                  onTap: () => _pickPhoto('before'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PhotoSlot(
                  label: 'Foto depois',
                  photo: _photos['after'],
                  onTap: () => _pickPhoto('after'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _PhotoSlot(
            key: const Key('novo-registro-nota-fiscal'),
            label: 'Foto da nota fiscal',
            icon: Icons.receipt_long_outlined,
            photo: _invoice,
            onTap: _pickInvoice,
          ),
          const SizedBox(height: 6),
          const MtFootnote('Os arquivos sobem depois que o registro é salvo.'),
        ],
      ),
    );
  }

  Widget _partRow(int index, _PartDraft part) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: part.name,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(hintText: 'Nome da peça'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: part.quantity,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(hintText: 'Qtd'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            controller: part.cost,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(hintText: 'R\$'),
          ),
        ),
        // The first row is the form's baseline and has nothing to remove.
        if (_parts.length > 1)
          IconButton(
            onPressed: () => setState(() => _parts.removeAt(index).dispose()),
            icon: const Icon(Icons.close, size: 18, color: MtColors.danger),
            tooltip: 'Remover peça',
          ),
      ],
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({
    super.key,
    required this.label,
    required this.onTap,
    this.photo,
    this.icon = Icons.add_a_photo_outlined,
  });

  final String label;
  final VoidCallback onTap;
  final _PickedPhoto? photo;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final picked = photo;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(MtSizes.controlRadius),
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: MtColors.slate50,
          border: Border.all(
            color: picked == null ? MtColors.slate200 : MtColors.petrol,
          ),
          borderRadius: BorderRadius.circular(MtSizes.controlRadius),
        ),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        child: picked == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: const Color(0xFF94A3B8)),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: MtColors.slate500,
                    ),
                  ),
                ],
              )
            : Image.memory(
                picked.bytes,
                fit: BoxFit.cover,
                width: double.infinity,
                height: 100,
              ),
      ),
    );
  }
}
