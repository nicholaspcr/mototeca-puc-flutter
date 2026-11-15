import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../app/routes.dart';
import '../models/history_note.dart';
import '../reports/history_pdf.dart';
import '../models/service_record.dart';
import '../repositories/service_record_repository.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import '../widgets/feedback.dart';
import '../widgets/mt_widgets.dart';
import '../widgets/note_sheet.dart';
import '../widgets/photo_image.dart';
import 'service_detail_screen.dart';

/// Consultar Placa — public plate lookup, no account required.
class PlateLookupScreen extends StatefulWidget {
  const PlateLookupScreen({super.key, this.initialPlate});

  /// Pre-filled when a mechanic arrives from the dashboard search box.
  final String? initialPlate;

  @override
  State<PlateLookupScreen> createState() => _PlateLookupScreenState();
}

class _PlateLookupScreenState extends State<PlateLookupScreen> {
  late final _plate = TextEditingController(text: widget.initialPlate ?? '');

  PlateHistory? _history;
  bool _searched = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if ((widget.initialPlate ?? '').trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _plate.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_plate.text.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      // No token is sent: this lookup is public by design, and it is the
      // reason the product exists.
      final history = await AppScope.read(context).serviceRecords
          .historyByPlate(_plate.text);
      if (!mounted) return;
      setState(() {
        _history = history;
        _searched = true;
      });
    } catch (error) {
      if (!mounted) return;
      showApiError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Downloads on the web; opens the share sheet on a phone.
  Future<void> _sharePdf(PlateHistory history) async {
    try {
      final bytes = await buildHistoryPdf(history);
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'historico-${history.vehicle.plate}.pdf',
      );
    } on Object {
      if (!mounted) return;
      showApiError(context, 'Não foi possível gerar o PDF.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MtAppBar(
        title: 'Consultar Placa',
        badge: MtBadge.shared(),
        status: 'Histórico público — não exige cadastro',
      ),
      body: ListView(
        padding: const EdgeInsets.all(MtSizes.screenPadding),
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: 'Placa',
                  child: TextField(
                    controller: _plate,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 15,
                    ),
                    decoration: const InputDecoration(hintText: 'EX: ABC1D23'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 116,
                child: ElevatedButton(
                  key: const Key('portal-consultar'),
                  onPressed: _busy ? null : _search,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(MtSizes.controlHeight),
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Consultar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (!_searched)
            const MtFootnote(
              'Não é necessário criar conta para consultar o histórico. '
              'Um cadastro só é pedido para reivindicar a propriedade da moto.',
              align: TextAlign.center,
            ),
          if (_searched && _history == null)
            MtCard(
              padding: const EdgeInsets.all(28),
              child: const Text(
                'Nenhum veículo encontrado para essa placa.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: MtColors.slate500),
              ),
            ),
          if (_history != null) ..._results(_history!),
        ],
      ),
    );
  }

  List<Widget> _results(PlateHistory history) {
    final vehicle = history.vehicle;
    final services = history.records.length;
    final notes = history.notes.length;
    final entries = <((DateTime, int?), Widget)>[
      for (final record in history.records)
        ((record.createdAt, record.mileageKm), _recordCard(record)),
      for (final note in history.notes)
        ((note.doneOn, note.mileageKm), _noteCard(note)),
    ]..sort((a, b) => newestFirst(a.$1, b.$1));

    return [
      MtCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              vehicle.labelWithYear,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              [
                'Placa ${vehicle.plate}',
                '$services ${services == 1 ? 'serviço registrado' : 'serviços registrados'}',
                if (notes > 0)
                  '$notes ${notes == 1 ? 'anotação do dono' : 'anotações do dono'}',
              ].join(' · '),
              style: const TextStyle(fontSize: 13, color: MtColors.slate500),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              key: const Key('portal-baixar-pdf'),
              onPressed: () => _sharePdf(history),
              child: const Text('Baixar PDF'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'Histórico de Serviços',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      if (entries.isEmpty)
        const MtEmptyState(
          message: 'Esta moto ainda não tem serviços registrados.',
          icon: Icons.history_outlined,
        ),
      for (final (_, card) in entries) ...[card, const SizedBox(height: 10)],
    ];
  }

  Widget _recordCard(ServiceRecord record) => _entryCard(
    key: Key('history-${record.id}'),
    title: record.operationsLabel,
    date: record.formattedDate,
    details: [
      record.workshopName,
      ?record.mechanicName,
      '${record.mileageKm} km',
    ],
    body: record.notes,
    onTap: () => Navigator.pushNamed(
      context,
      Routes.serviceDetail,
      arguments: ServiceDetailArgs(record: record),
    ),
  );

  Widget _noteCard(HistoryNote note) => _entryCard(
    key: Key('history-note-${note.id}'),
    title: note.description,
    date: formatDate(note.doneOn),
    details: [
      if (note.mileageKm != null) '${note.mileageKm} km',
      if (note.photoUrl != null) 'com foto',
    ],
    badge: const MtBadge.ownerNote(),
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

  Widget _entryCard({
    required Key key,
    required String title,
    required String date,
    required List<String> details,
    required VoidCallback onTap,
    String? body,
    Widget? badge,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(MtSizes.cardRadius),
      child: MtCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  date,
                  style: const TextStyle(
                    fontSize: 12,
                    color: MtColors.slate500,
                  ),
                ),
              ],
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                details.join(' · '),
                style: const TextStyle(fontSize: 12, color: MtColors.slate500),
              ),
            ],
            if (body != null && body.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(body, style: const TextStyle(fontSize: 13, height: 1.4)),
            ],
            if (badge != null) ...[const SizedBox(height: 8), badge],
          ],
        ),
      ),
    );
  }
}
