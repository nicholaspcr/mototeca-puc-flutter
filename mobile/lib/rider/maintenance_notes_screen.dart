import 'package:flutter/material.dart';

import '../models/service_record.dart';
import '../state/app_scope.dart';
import '../storage/garage_store.dart';
import '../theme.dart';
import '../widgets/feedback.dart';
import '../widgets/mt_widgets.dart';

/// Anotações — services the rider wrote down for one bike on the device.
class MaintenanceNotesScreen extends StatefulWidget {
  const MaintenanceNotesScreen({super.key, required this.bike});

  final LocalBike bike;

  @override
  State<MaintenanceNotesScreen> createState() => _MaintenanceNotesScreenState();
}

class _MaintenanceNotesScreenState extends State<MaintenanceNotesScreen> {
  var _notes = <MaintenanceNote>[];
  var _loading = true;

  LocalGarage get _garage => AppScope.read(context).garage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
      builder: (_) => _NoteDialog(bikeId: widget.bike.id!, initial: note),
    );
    if (saved == null || !mounted) return;
    try {
      await _garage.saveNote(saved);
      await _load();
      if (mounted) {
        showSuccess(
          context,
          note == null ? 'Anotação salva.' : 'Anotação atualizada.',
        );
      }
    } on Object {
      if (mounted) showApiError(context, localSaveFailed);
    }
  }

  Future<void> _remove(MaintenanceNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar anotação'),
        content: Text('"${note.description}" sai deste aparelho.'),
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
    try {
      await _garage.removeNote(note.id!);
      await _load();
      if (mounted) showSuccess(context, 'Anotação apagada.');
    } on Object {
      if (mounted) showApiError(context, localSaveFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final garage = AppScope.of(context).garage;

    return Scaffold(
      appBar: MtAppBar(title: 'Anotações', status: 'Salvas neste aparelho'),
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
    if (_notes.isEmpty) {
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
      itemCount: _notes.length,
      itemBuilder: (context, index) {
        final note = _notes[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: MtCard(
            padding: EdgeInsets.zero,
            child: Material(
              type: MaterialType.transparency,
              child: ListTile(
                key: Key('anotacao-${note.id}'),
                title: Text(note.description),
                subtitle: Text(
                  [
                    formatDate(note.doneOn),
                    if (note.mileageKm != null) '${note.mileageKm} km',
                    if (note.costCents != null) formatCents(note.costCents!),
                  ].join(' · '),
                ),
                onTap: () => _edit(note),
                onLongPress: () => _remove(note),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.bikeId, this.initial});

  final int bikeId;
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
