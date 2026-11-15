import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/service_record.dart';
import '../repositories/service_record_repository.dart';

const _petrol = PdfColor.fromInt(0xFF1B4965);
const _slate = PdfColor.fromInt(0xFF64748B);

/// The plate history as a PDF — what an owner hands a buyer when selling.
/// Built on the device from data already fetched, so it needs no endpoint.
Future<Uint8List> buildHistoryPdf(PlateHistory history, {DateTime? now}) {
  final vehicle = history.vehicle;
  final generated = formatDate(now ?? DateTime.now());

  final document = pw.Document(
    title: 'Histórico ${vehicle.plate}',
    author: 'Mototeca',
  );

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Mototeca',
            style: pw.TextStyle(color: _petrol, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 16),
        ],
      ),
      footer: (context) => pw.Text(
        'Gerado em $generated · página ${context.pageNumber} de ${context.pagesCount}',
        style: const pw.TextStyle(color: _slate, fontSize: 9),
      ),
      build: (_) => [
        pw.Text(
          '${vehicle.labelWithYear} · placa ${vehicle.plate}',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          '${history.records.length} serviço(s) registrado(s) por oficinas',
          style: const pw.TextStyle(color: _slate),
        ),
        pw.SizedBox(height: 20),
        if (history.records.isEmpty)
          pw.Text('Nenhum serviço registrado para esta placa.')
        else
          _table(
            headers: ['Data', 'Serviço', 'Oficina', 'Km', 'Valor'],
            rows: [
              for (final record in history.records)
                [
                  record.formattedDate,
                  record.operationsLabel,
                  _latin1(record.workshopName),
                  '${record.mileageKm}',
                  _cost(record.costCents),
                ],
            ],
            widths: {
              0: const pw.FixedColumnWidth(62),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FixedColumnWidth(50),
              4: const pw.FixedColumnWidth(70),
            },
          ),
        if (history.notes.isNotEmpty) ...[
          pw.SizedBox(height: 24),
          pw.Text(
            'Anotações do dono',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Informadas pelo próprio dono; nenhuma oficina as confirmou.',
            style: const pw.TextStyle(color: _slate),
          ),
          pw.SizedBox(height: 10),
          _table(
            headers: ['Data', 'O que foi feito', 'Km', 'Valor'],
            rows: [
              for (final note in history.notes)
                [
                  formatDate(note.doneOn),
                  _latin1(note.description),
                  note.mileageKm == null ? '-' : '${note.mileageKm}',
                  _cost(note.costCents),
                ],
            ],
            widths: {
              0: const pw.FixedColumnWidth(62),
              1: const pw.FlexColumnWidth(5),
              2: const pw.FixedColumnWidth(50),
              3: const pw.FixedColumnWidth(70),
            },
          ),
        ],
      ],
    ),
  );

  return document.save();
}

// The built-in font is Latin-1 only, which has no em dash.
String _cost(int? cents) => cents == null ? '-' : formatCents(cents);

/// Typed text can hold what the built-in font cannot draw, such as the curly
/// quotes a phone keyboard inserts.
String _latin1(String text) => String.fromCharCodes(
  text.runes.map(
    (rune) => switch (rune) {
      < 0x100 => rune,
      0x2018 || 0x2019 => 0x27,
      0x201C || 0x201D => 0x22,
      0x2013 || 0x2014 => 0x2D,
      _ => 0x3F,
    },
  ),
);

pw.Widget _table({
  required List<String> headers,
  required List<List<String>> rows,
  required Map<int, pw.TableColumnWidth> widths,
}) => pw.TableHelper.fromTextArray(
  headers: headers,
  data: rows,
  headerStyle: pw.TextStyle(
    color: PdfColors.white,
    fontWeight: pw.FontWeight.bold,
  ),
  headerDecoration: const pw.BoxDecoration(color: _petrol),
  cellStyle: const pw.TextStyle(fontSize: 10),
  columnWidths: widths,
);
