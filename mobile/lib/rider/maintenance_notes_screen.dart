import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_exception.dart';
import '../app/routes.dart';
import '../models/history_note.dart';
import '../models/service_record.dart';
import '../repositories/service_record_repository.dart';
import '../shared/service_detail_screen.dart';
import '../state/app_scope.dart';
import '../storage/garage_store.dart';
import '../theme.dart';
import '../widgets/feedback.dart';
import '../widgets/mt_widgets.dart';
import '../widgets/note_sheet.dart';
import '../widgets/photo_image.dart';
import '../widgets/photo_slot.dart';

typedef _Entry = ({
  DateTime date,
  int? km,
  MaintenanceNote? note,
  HistoryNote? published,
  ServiceRecord? service,
});

/// Anotações — services the rider wrote down for one bike on the device.
/// Signed in, the plate's history joins the same list, and notes on a bike
/// linked to the account are published to it.
class MaintenanceNotesScreen extends StatefulWidget {
  const MaintenanceNotesScreen({super.key, required this.bike});

  final LocalBike bike;

  @override
  State<MaintenanceNotesScreen> createState() => _MaintenanceNotesScreenState();
}

class _MaintenanceNotesScreenState extends State<MaintenanceNotesScreen> {
  var _notes = <MaintenanceNote>[];
  PlateHistory? _history;
  var _historyFailed = false;
  var _loading = true;

  LocalGarage get _garage => AppScope.read(context).garage;

  bool get _signedIn => AppScope.read(context).owner != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  /// Publishes what is pending first, so the list shows it as published.
  Future<void> _refresh() async {
    await _load();
    if (!_signedIn || !mounted) return;
    if (await AppScope.read(context).publishNotes() > 0) await _load();
    await _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final history = await AppScope.read(context).serviceRecords
          .historyByPlate(widget.bike.plate);
      if (!mounted) return;
      setState(() {
        _history = history;
        _historyFailed = false;
      });
    } on Object {
      if (mounted) setState(() => _historyFailed = true);
    }
  }

  Future<void> _load() async {
    final notes = await _garage.notes(widget.bike.id!);
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _loading = false;
    });
  }

  Future<void> _edit([MaintenanceNote? note]) async {
    final saved = await showDialog<MaintenanceNote>(
      context: context,
      builder: (_) => _NoteDialog(
        bikeId: widget.bike.id!,
        initial: note,
        signedIn: _signedIn,
      ),
    );
    if (saved == null || !mounted) return;
    try {
      await _garage.saveNote(saved);
      if (mounted) {
        showSuccess(
          context,
          note == null ? 'Anotação salva.' : 'Anotação atualizada.',
        );
      }
    } on Object {
      if (mounted) showApiError(context, localSaveFailed);
      return;
    }
    await _refresh();
  }

  void _open(MaintenanceNote note) {
    if (!note.isPublished) {
      _edit(note);
      return;
    }
    showNoteSheet(
      context,
      description: note.description,
      doneOn: note.doneOn,
      mileageKm: note.mileageKm,
      costCents: note.costCents,
      photo: switch (note.photo) {
        final bytes? => MemoryImage(bytes),
        null => null,
      },
      badge: 'Sua anotação · no histórico da placa',
      onDelete: () => _remove(note),
    );
  }

  Future<void> _remove(MaintenanceNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar anotação'),
        content: Text(
          note.isPublished
              ? '"${note.description}" sai deste aparelho e do histórico '
                    'público da placa.'
              : '"${note.description}" sai deste aparelho.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const Key('anotacao-apagar-confirmar'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final state = AppScope.read(context);
    try {
      if (note.serverId case final id?) await _unpublish(state, id);
      await _garage.removeNote(note.id!);
      await _load();
      if (mounted) showSuccess(context, 'Anotação apagada.');
      if (note.isPublished) await _loadHistory();
    } on ApiException catch (error) {
      if (mounted) showApiError(context, error);
    } on Object {
      if (mounted) showApiError(context, localSaveFailed);
    }
  }

  /// Already gone from the server, or the bike was sold: either way only the
  /// device copy is left to delete.
  Future<void> _unpublish(AppState state, String id) async {
    if (state.owner == null) {
      throw const ApiException(
        ApiErrorCode.unauthenticated,
        'Entre na conta para apagar uma anotação do histórico.',
      );
    }
    try {
      await state.owners.deleteNote(id);
    } on ApiException catch (error) {
      if (error.code != ApiErrorCode.notFound) rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final garage = AppScope.of(context).garage;

    return Scaffold(
      appBar: _signedIn
          ? const MtAppBar(
              title: 'Manutenções',
              status: 'Anotações e serviços das oficinas',
            )
          : const MtAppBar(title: 'Anotações', status: 'Salvas neste aparelho'),
      floatingActionButton: FloatingActionButton(
        key: const Key('anotacao-nova'),
        backgroundColor: MtColors.petrol,
        foregroundColor: Colors.white,
        tooltip: 'Nova anotação',
        onPressed: _edit,
        child: const Icon(Icons.add),
      ),
      body: ListenableBuilder(
        listenable: garage,
        builder: (context, _) {
          final bike = garage.bikes.firstWhere(
            (bike) => bike.id == widget.bike.id,
            orElse: () => widget.bike,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  MtSizes.screenPadding,
                  MtSizes.screenPadding,
                  MtSizes.screenPadding,
                  8,
                ),
                child: Text(
                  '${bike.plate} · ${bike.label} · ${bike.mileageKm} km',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(child: _list()),
            ],
          );
        },
      ),
    );
  }

  Widget _list() {
    if (_loading) return const MtLoading();
    final mine = {for (final note in _notes) ?note.serverId};
    final history = _history;
    final entries = <_Entry>[
      for (final note in _notes)
        (
          date: note.doneOn,
          km: note.mileageKm,
          note: note,
          published: null,
          service: null,
        ),
      if (history != null) ...[
        for (final service in history.records)
          (
            date: service.createdAt,
            km: service.mileageKm,
            note: null,
            published: null,
            service: service,
          ),
        for (final published in history.notes)
          if (!mine.contains(published.id))
            (
              date: published.doneOn,
              km: published.mileageKm,
              note: null,
              published: published,
              service: null,
            ),
      ],
    ]..sort((a, b) => newestFirst((a.date, a.km), (b.date, b.km)));

    if (entries.isEmpty && !_historyFailed) {
      return const MtEmptyState(
        message:
            'Nenhuma anotação ainda.\n'
            'Toque em + para registrar uma manutenção.',
        icon: Icons.edit_note,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        MtSizes.screenPadding,
        8,
        MtSizes.screenPadding,
        96,
      ),
      itemCount: entries.length + (_historyFailed ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == entries.length) {
          return const MtFootnote(
            'Não foi possível carregar o histórico da placa.',
          );
        }
        final entry = entries[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: entry.note != null
              ? _noteCard(entry.note!)
              : entry.published != null
              ? _publishedCard(entry.published!)
              : _serviceCard(entry.service!),
        );
      },
    );
  }

  Widget _noteCard(MaintenanceNote note) => _entryCard(
    key: Key('anotacao-${note.id}'),
    badge: MtBadge.ownerNote(
      label: note.isPublished
          ? 'Sua anotação · no histórico da placa'
          : 'Sua anotação · só neste aparelho',
    ),
    title: note.description,
    details: [
      formatDate(note.doneOn),
      if (note.mileageKm != null) '${note.mileageKm} km',
      if (note.costCents != null) formatCents(note.costCents!),
      if (note.photo != null) 'com foto',
    ],
    onTap: () => _open(note),
    onLongPress: () => _remove(note),
  );

  /// Written on another phone, or by a previous owner.
  Widget _publishedCard(HistoryNote note) => _entryCard(
    key: Key('anotacao-publicada-${note.id}'),
    badge: const MtBadge.ownerNote(),
    title: note.description,
    details: [
      formatDate(note.doneOn),
      if (note.mileageKm != null) '${note.mileageKm} km',
      if (note.costCents != null) formatCents(note.costCents!),
      if (note.photoUrl != null) 'com foto',
    ],
    onTap: () => showNoteSheet(
      context,
      description: note.description,
      doneOn: note.doneOn,
      mileageKm: note.mileageKm,
      costCents: note.costCents,
      photo: switch (note.photoUrl) {
        final url? => photoImage(url),
        null => null,
      },
    ),
  );

  Widget _serviceCard(ServiceRecord service) => _entryCard(
    key: Key('servico-${service.id}'),
    badge: MtBadge(
      label: 'Oficina · ${service.workshopName}',
      background: MtColors.petrolTint,
      foreground: MtColors.petrol,
    ),
    title: service.operationsLabel,
    details: [
      service.formattedDate,
      '${service.mileageKm} km',
      if (service.costCents != null) service.formattedCost,
    ],
    onTap: () => Navigator.pushNamed(
      context,
      Routes.serviceDetail,
      arguments: ServiceDetailArgs(record: service),
    ),
  );

  Widget _entryCard({
    required Key key,
    required Widget badge,
    required String title,
    required List<String> details,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return MtCard(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          key: key,
          title: Text(title),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(details.join(' · ')),
              const SizedBox(height: 6),
              badge,
            ],
          ),
          onTap: onTap,
          onLongPress: onLongPress,
        ),
      ),
    );
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({
    required this.bikeId,
    required this.signedIn,
    this.initial,
  });

  final int bikeId;
  final bool signedIn;
  final MaintenanceNote? initial;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late var _doneOn = widget.initial?.doneOn ?? DateTime.now();
  late final _description = TextEditingController(
    text: widget.initial?.description,
  );
  late final _mileage = TextEditingController(
    text: widget.initial?.mileageKm?.toString(),
  );
  late final _cost = TextEditingController(
    text: widget.initial?.costCents == null
        ? null
        : formatCents(widget.initial!.costCents!),
  );
  late var _photo = switch (widget.initial) {
    MaintenanceNote(:final photo?, :final photoType) => PickedPhoto(
      bytes: photo,
      name: 'foto',
      mimeType: photoType ?? 'image/jpeg',
    ),
    _ => null,
  };

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (picked == null) return;
    final photo = PickedPhoto(
      bytes: await picked.readAsBytes(),
      name: picked.name,
      mimeType: picked.mimeType ?? 'image/jpeg',
    );
    if (mounted) setState(() => _photo = photo);
  }

  @override
  void dispose() {
    _description.dispose();
    _mileage.dispose();
    _cost.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _doneOn,
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _doneOn = picked);
  }

  void _submit() {
    final description = _description.text.trim();
    final mileageText = _mileage.text.trim().replaceAll('.', '');
    final mileage = int.tryParse(mileageText);
    int? cost;
    try {
      cost = parseCents(_cost.text);
    } on FormatException {
      return showApiError(context, 'Valor inválido.');
    }
    if (description.isEmpty) {
      return showApiError(context, 'Descreva o que foi feito.');
    }
    if (mileageText.isNotEmpty && (mileage == null || mileage < 0)) {
      return showApiError(context, 'Quilometragem inválida.');
    }
    Navigator.pop(
      context,
      MaintenanceNote(
        id: widget.initial?.id,
        bikeId: widget.bikeId,
        doneOn: _doneOn,
        description: description,
        mileageKm: mileage,
        costCents: cost,
        photo: _photo?.bytes,
        photoType: _photo?.mimeType,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Nova anotação' : 'Editar anotação'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MtField(
              key: const Key('anotacao-descricao'),
              label: 'O que foi feito',
              hint: 'Troca de óleo e filtro',
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: [LengthLimitingTextInputFormatter(500)],
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              key: const Key('anotacao-data'),
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(formatDate(_doneOn)),
            ),
            const SizedBox(height: 14),
            MtField(
              key: const Key('anotacao-km'),
              label: 'Quilometragem',
              hint: '18420',
              controller: _mileage,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 14),
            MtField(
              key: const Key('anotacao-valor'),
              label: 'Valor (opcional)',
              hint: 'R\$ 45,00',
              controller: _cost,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 14),
            PhotoSlot(
              key: const Key('anotacao-foto-escolher'),
              label: 'Foto (opcional)',
              photos: [?_photo],
              onTap: _pickPhoto,
              onClear: () => setState(() => _photo = null),
            ),
            if (widget.signedIn) ...[
              const SizedBox(height: 12),
              const MtFootnote(
                'Em uma moto vinculada à conta, a anotação e a foto entram no '
                'histórico público da placa, que oficinas e compradores veem.',
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          key: const Key('anotacao-salvar'),
          onPressed: _submit,
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
