import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mototeca/api/api_client.dart';
import 'package:mototeca/demo/demo_backend.dart';
import 'package:mototeca/demo/demo_client.dart';
import 'package:mototeca/models/service_operation.dart';
import 'package:mototeca/models/service_record.dart';
import 'package:mototeca/models/vehicle.dart';
import 'package:mototeca/repositories/service_record_repository.dart';
import 'package:mototeca/repositories/workshop_repository.dart';
import 'package:mototeca/storage/garage_store.dart';
import 'package:mototeca/storage/outbox_store.dart';
import 'package:sqflite/sqflite.dart';

import 'test_database.dart';

OutboxDraft draft(String plate, {List<Part> parts = const []}) => OutboxDraft(
  plate: plate,
  vehicleLabel: 'Honda CG',
  operations: const [ServiceOperation.tires, ServiceOperation.brakes],
  mileageKm: 18500,
  savedAt: DateTime(2026, 10, 1),
  parts: parts,
);

void main() {
  group('input validation', () {
    test('accepts old and Mercosul plates only', () {
      expect(isValidPlate('abc-1234'), isTrue);
      expect(isValidPlate('ABC1D23'), isTrue);
      expect(isValidPlate('AB12'), isFalse);
      expect(isValidPlate('ABCD123'), isFalse);
    });

    test('reads and writes money as integer cents', () {
      expect(parseCents('R\$ 45,90'), 4590);
      expect(parseCents(''), isNull);
      expect(() => parseCents('1,2,3'), throwsFormatException);
      expect(formatCents(100099), r'R$ 1000,99');
    });
  });

  group('schema', () {
    test(
      'rejects negative values, orphans and unknown attachment kinds',
      () async {
        final db = await testDatabase().database;
        final now = DateTime(2026).toIso8601String();

        await expectLater(
          db.insert('bikes', {
            'plate': 'ABC1D23',
            'label': 'A',
            'mileage_km': -1,
            'created_at': now,
          }),
          throwsA(isA<DatabaseException>()),
        );
        await expectLater(
          db.insert('maintenance_notes', {
            'bike_id': 999,
            'done_on': now,
            'description': 'x',
          }),
          throwsA(isA<DatabaseException>()),
        );
        final draftId = await db.insert('outbox_drafts', {
          ...draft('ABC1D23').toRow(),
        });
        await expectLater(
          db.insert('outbox_attachments', {
            'draft_id': draftId,
            'kind': 'video',
            'filename': 'x',
            'content_type': 'video/mp4',
            'bytes': Uint8List(1),
          }),
          throwsA(isA<DatabaseException>()),
        );
      },
    );
  });

  group('LocalGarage', () {
    test('saves, updates and removes a bike with a normalized plate', () async {
      final garage = LocalGarage(testDatabase());

      await garage.save(const LocalBike(plate: 'abc-1d23', label: 'Honda CG'));
      final bike = garage.bikes.single;
      expect(bike.plate, 'ABC1D23');

      await garage.save(
        LocalBike(id: bike.id, plate: bike.plate, label: 'Honda CG 160'),
      );
      expect(garage.bikes.single.label, 'Honda CG 160');

      await garage.remove(bike.id!);
      expect(garage.isEmpty, isTrue);
    });

    test('a repeated plate is refused and nothing is written', () async {
      final garage = LocalGarage(testDatabase());
      await garage.save(const LocalBike(plate: 'ABC1D23', label: 'A'));

      await expectLater(
        garage.save(const LocalBike(plate: 'abc1d23', label: 'B')),
        throwsA(isA<DuplicatePlateException>()),
      );
      expect(garage.bikes.single.label, 'A');
    });

    test('notes raise the odometer, never lower it', () async {
      final garage = LocalGarage(testDatabase());
      await garage.save(
        const LocalBike(plate: 'ABC1D23', label: 'A', mileageKm: 1000),
      );
      final bikeId = garage.bikes.single.id!;

      Future<void> note(String text, int km, int month) => garage.saveNote(
        MaintenanceNote(
          bikeId: bikeId,
          doneOn: DateTime(2026, month),
          description: text,
          mileageKm: km,
        ),
      );
      await note('Corrente', 4000, 9);
      await note('Óleo', 3000, 8);

      expect(garage.bikes.single.mileageKm, 4000);
      final notes = await garage.notes(bikeId);
      expect(notes.map((n) => n.description), ['Corrente', 'Óleo']);
    });

    test('removing a bike removes its notes', () async {
      final database = testDatabase();
      final garage = LocalGarage(database);
      await garage.save(const LocalBike(plate: 'ABC1D23', label: 'A'));
      final bikeId = garage.bikes.single.id!;
      await garage.saveNote(
        MaintenanceNote(
          bikeId: bikeId,
          doneOn: DateTime(2026),
          description: 'x',
        ),
      );

      await garage.remove(bikeId);

      final db = await database.database;
      expect(await db.query('maintenance_notes'), isEmpty);
    });
  });

  group('Outbox', () {
    test('a draft survives a reload with its parts and files', () async {
      final database = testDatabase();
      await Outbox(database).add(
        OutboxDraft(
          plate: 'ABC1D23',
          vehicleLabel: 'Honda CG',
          operations: const [ServiceOperation.tires, ServiceOperation.brakes],
          mileageKm: 18500,
          savedAt: DateTime(2026, 10, 1),
          costCents: 24550,
          parts: const [Part(name: 'Pneu traseiro', quantity: 1)],
          attachments: [
            OutboxAttachment(
              kind: 'photo',
              phase: 'after',
              filename: 'pneu.jpg',
              contentType: 'image/jpeg',
              bytes: Uint8List.fromList([1, 2, 3]),
            ),
          ],
        ),
      );

      final reloaded = Outbox(database);
      await reloaded.load();
      final saved = reloaded.drafts.single;
      expect(saved.operations, [
        ServiceOperation.tires,
        ServiceOperation.brakes,
      ]);
      expect(saved.parts.single.name, 'Pneu traseiro');
      expect(saved.attachments.single.bytes, [1, 2, 3]);

      await reloaded.remove(saved.id!);
      final db = await database.database;
      expect(await db.query('outbox_parts'), isEmpty);
      expect(await db.query('outbox_attachments'), isEmpty);
    });

    test('a draft with a bad part is not half-written', () async {
      final database = testDatabase();
      final outbox = Outbox(database);

      await expectLater(
        outbox.add(
          draft('ABC1D23', parts: const [Part(name: 'Pneu', quantity: 0)]),
        ),
        throwsA(isA<DatabaseException>()),
      );

      final db = await database.database;
      expect(await db.query('outbox_drafts'), isEmpty);
      expect(await db.query('outbox_operations'), isEmpty);
    });

    test('flush deletes what the server accepts and keeps the rest', () async {
      final client = ApiClient(
        baseUrl: 'demo://mototeca',
        httpClient: DemoClient(backend: DemoBackend(), latency: Duration.zero),
      );
      final session = await WorkshopRepository(client)
          .login(cnpj: demoCNPJ, password: demoPassword);
      client.authToken = session.token;

      final outbox = Outbox(testDatabase());
      await outbox.add(draft(demoPlate));
      await outbox.add(draft('XYZ9A99'));

      final result = await outbox.flush(ServiceRecordRepository(client));

      expect((result.sent, result.failed), (1, 1));
      expect(outbox.drafts.single.plate, 'XYZ9A99');
    });
  });
}
