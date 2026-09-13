import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mototeca/models/service_record.dart';
import 'package:mototeca/reports/history_pdf.dart';
import 'package:mototeca/repositories/service_record_repository.dart';

import 'fake_api.dart';

void main() {
  test('builds a PDF of the plate history', () async {
    final history = PlateHistory(
      vehicle: ServiceRecord.fromJson(FakeApi.recordJson).vehicle,
      records: [ServiceRecord.fromJson(FakeApi.recordJson)],
    );

    final bytes = await buildHistoryPdf(history, now: DateTime(2026, 9, 13));

    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  test('an empty history still produces a document', () async {
    final history = PlateHistory(
      vehicle: ServiceRecord.fromJson(FakeApi.recordJson).vehicle,
      records: const [],
    );

    final bytes = await buildHistoryPdf(history);

    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
  });
}
