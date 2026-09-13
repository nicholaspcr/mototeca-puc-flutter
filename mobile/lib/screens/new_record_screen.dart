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

  _PartDraft.from(Part part)
    : name = TextEditingController(text: part.name),
      quantity = TextEditingController(text: '${part.quantity}'),
      cost = TextEditingController(
        text: part.costCents == null ? '' : formatCents(part.costCents!),
      );

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

typedef _Draft = ({
  List<ServiceOperation> operations,
  int mileageKm,
  String mechanicName,
  int? costCents,
  String notes,
  List<Part> parts,
});

/// More would outgrow what a shop's connection uploads comfortably, and the
/// server caps a record's files anyway.
const maxPhotosPerPhase = 5;

/// Novo Registro — the app's main action (design/NewRecord.dc.html). Also
/// corrects an existing record, since a correction is a new record too.
class NewRecordScreen extends StatefulWidget {
  const NewRecordScreen({super.key, this.initialPlate, this.revising});

  /// Pre-filled when the mechanic arrives from the dashboard search box.
  final String? initialPlate;

  /// The record being corrected; its fields start the form.
  final ServiceRecord? revising;

  @override
  State<NewRecordScreen> createState() => _NewRecordScreenState();
}

class _NewRecordScreenState extends State<NewRecordScreen> {
  late final _plate = TextEditingController(
    text: widget.revising?.vehicle.plate ?? widget.initialPlate ?? '',
  );
  late final _mechanic = TextEditingController(
    text: widget.revising?.mechanicName ?? '',
  );
  late final _mileage = TextEditingController(
    text: widget.revising?.mileageKm.toString() ?? '',
  );
  late final _cost = TextEditingController(
    text: switch (widget.revising?.costCents) {
      final cents? => formatCents(cents),
      null => '',
    },
  );
  late final _notes = TextEditingController(text: widget.revising?.notes ?? '');
  late final _parts = [
    for (final part in widget.revising?.parts ?? const <Part>[])
      _PartDraft.from(part),
    if (widget.revising?.parts.isEmpty ?? true) _PartDraft(),
  ];
  late final _selectedOps = {...?widget.revising?.operations};

  final _picker = ImagePicker();
  final _photos = <String, List<_PickedPhoto>>{'before': [], 'after': []};
  _PickedPhoto? _invoice;

  // A correction stays on the same bike, so its vehicle is known up front.
  late VehicleSummary? _vehicle = widget.revising?.vehicle;
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
        _vehicle = vehicle?.summary;
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

    final draft = (
      operations: _selectedOps.toList(),
      mileageKm: mileage,
      mechanicName: _mechanic.text,
      costCents: costCents,
      notes: _notes.text,
      parts: parts,
    );
    final original = widget.revising;

    setState(() => _saving = true);
    try {
      final record = original == null
          ? await _create(vehicle.plate, draft)
          : await _revise(original, draft);
      if (record == null || !mounted) return;

      // Attachments need the record to exist, so they follow the save. A
      // failed photo must not discard a saved record — the record is the part
      // that matters.
      final failed = await _uploadAttachments(record.id);
      if (!mounted) return;
      final saved = original == null ? 'Registro salvo' : 'Correção salva';
      showSuccess(
        context,
        failed == 0
            ? '$saved no histórico da moto.'
            : '$saved, mas $failed arquivo(s) não subiram.',
      );
      // A new record only tells the dashboard its feed is stale; a correction
      // hands back the record that replaced the one on screen.
      Navigator.pop(context, original == null ? true : record);
    } catch (error) {
      if (!mounted) return;
      showApiError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Returns null when the mechanic declines to save a lower mileage.
  Future<ServiceRecord?> _create(String plate, _Draft draft) async {
    final repository = AppScope.read(context).serviceRecords;
    Future<ServiceRecord> create({bool confirmLowerMileage = false}) =>
        repository.create(
          plate: plate,
          operations: draft.operations,
          mileageKm: draft.mileageKm,
          mechanicName: draft.mechanicName,
          costCents: draft.costCents,
          notes: draft.notes,
          parts: draft.parts,
          confirmLowerMileage: confirmLowerMileage,
        );

    try {
      return await create();
    } on ApiException catch (error) {
      if (error.code != ApiErrorCode.failedPrecondition || !mounted) rethrow;
      // No spinner behind the question: nothing is saving while it waits.
      setState(() => _saving = false);
      if (!await _confirmLowerMileage(error.message) || !mounted) return null;
      setState(() => _saving = true);
      return create(confirmLowerMileage: true);
    }
  }

  Future<ServiceRecord> _revise(ServiceRecord original, _Draft draft) {
    return AppScope.read(context).serviceRecords.revise(
      recordId: original.id,
      operations: draft.operations,
      mileageKm: draft.mileageKm,
      mechanicName: draft.mechanicName,
      costCents: draft.costCents,
      notes: draft.notes,
      parts: draft.parts,
    );
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
      for (final MapEntry(key: phase, value: photos) in _photos.entries)
        for (final photo in photos) (file: photo, kind: 'photo', phase: phase),
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

  // Shop connections are poor and the API caps uploads at 8 MiB
  // (ARCHITECTURE.md §9).
  static const _maxWidth = 1600.0;
  static const _imageQuality = 80;

  static Future<_PickedPhoto> _read(XFile file) async => _PickedPhoto(
    bytes: await file.readAsBytes(),
    name: file.name,
    mimeType: file.mimeType ?? 'image/jpeg',
  );

  Future<void> _pickPhotos(String phase) async {
    final room = maxPhotosPerPhase - _photos[phase]!.length;
    if (room <= 0) {
      showApiError(context, 'Até $maxPhotosPerPhase fotos por etapa.');
      return;
    }

    final picked = await _picker.pickMultiImage(
      maxWidth: _maxWidth,
      imageQuality: _imageQuality,
      limit: room,
    );
    final photos = await Future.wait(picked.take(room).map(_read));
    if (photos.isEmpty || !mounted) return;
    setState(() => _photos[phase] = [..._photos[phase]!, ...photos]);
  }

  Future<void> _pickInvoice() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: _maxWidth,
      imageQuality: _imageQuality,
    );
    if (picked == null) return;
    final invoice = await _read(picked);
    if (!mounted) return;
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
      appBar: AppBar(
        title: Text(
          widget.revising == null ? 'Novo Registro' : 'Corrigir Registro',
        ),
      ),
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
                  : Text(
                      widget.revising == null
                          ? 'Salvar Registro'
                          : 'Salvar Correção',
                    ),
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
          if (widget.revising == null)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _plate,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 15,
                    ),
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
                  key: const Key('novo-registro-fotos-antes'),
                  label: 'Fotos antes',
                  photos: _photos['before']!,
                  onTap: () => _pickPhotos('before'),
                  onClear: () => setState(() => _photos['before'] = []),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PhotoSlot(
                  key: const Key('novo-registro-fotos-depois'),
                  label: 'Fotos depois',
                  photos: _photos['after']!,
                  onTap: () => _pickPhotos('after'),
                  onClear: () => setState(() => _photos['after'] = []),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _PhotoSlot(
            key: const Key('novo-registro-nota-fiscal'),
            label: 'Foto da nota fiscal',
            icon: Icons.receipt_long_outlined,
            photos: [?_invoice],
            onTap: _pickInvoice,
            onClear: () => setState(() => _invoice = null),
          ),
          const SizedBox(height: 6),
          MtFootnote(
            widget.revising == null
                ? 'Os arquivos sobem depois que o registro é salvo.'
                : 'Fotos e nota já anexadas passam para a correção; '
                      'as escolhidas aqui são somadas a elas.',
          ),
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

/// Tapping adds photos (or replaces the invoice); the corner button clears
/// the slot.
class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({
    super.key,
    required this.label,
    required this.photos,
    required this.onTap,
    required this.onClear,
    this.icon = Icons.add_a_photo_outlined,
  });

  final String label;
  final List<_PickedPhoto> photos;
  final VoidCallback onTap;
  final VoidCallback onClear;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cover = photos.firstOrNull;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(MtSizes.controlRadius),
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: MtColors.slate50,
          border: Border.all(
            color: cover == null ? MtColors.slate200 : MtColors.petrol,
          ),
          borderRadius: BorderRadius.circular(MtSizes.controlRadius),
        ),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        child: cover == null
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
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(cover.bytes, fit: BoxFit.cover),
                  if (photos.length > 1)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: _Badge(child: Text('${photos.length} fotos')),
                    ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      tooltip: 'Remover',
                      onPressed: onClear,
                      icon: const _Badge(
                        child: Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: MtColors.graphite.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(9999),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontSize: 11, color: Colors.white),
        child: child,
      ),
    );
  }
}
