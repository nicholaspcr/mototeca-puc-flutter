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
          pw.TableHelper.fromTextArray(
            headers: ['Data', 'Serviço', 'Oficina', 'Km', 'Valor'],
            data: [
              for (final record in history.records)
                [
                  record.formattedDate,
                  record.operationsLabel,
                  record.workshopName,
                  '${record.mileageKm}',
                  // The built-in font is Latin-1 only, which has no em dash.
                  record.costCents == null ? '-' : record.formattedCost,
                ],
            ],
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
            headerDecoration: const pw.BoxDecoration(color: _petrol),
            cellStyle: const pw.TextStyle(fontSize: 10),
            columnWidths: {
              0: const pw.FixedColumnWidth(62),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FixedColumnWidth(50),
              4: const pw.FixedColumnWidth(70),
            },
          ),
      ],
    ),
  );

  return document.save();
}
