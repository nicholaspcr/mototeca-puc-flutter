import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mototeca/models/service_operation.dart';
import 'package:mototeca/models/service_record.dart';
import 'package:mototeca/storage/garage_store.dart';
import 'package:mototeca/storage/outbox_store.dart';

import 'test_database.dart';

void main() {
  group('LocalGarage', () {
    test('creates, reads, updates and deletes a bike', () async {
      final garage = LocalGarage(testDatabase());

      await garage.save(
        const LocalBike(plate: 'abc-1d23', label: 'Honda CG', year: 2022),
      );
      final bike = garage.bikes.single;
      expect(bike.plate, 'ABC1D23');
      expect(bike.id, isNotNull);

      await garage.save(
        LocalBike(id: bike.id, plate: bike.plate, label: 'Honda CG 160'),
      );
      expect(garage.bikes.single.label, 'Honda CG 160');

      await garage.remove(bike.id!);
      expect(garage.isEmpty, isTrue);
    });

    test('refuses a plate that is already in the garage', () async {
      final garage = LocalGarage(testDatabase());
      await garage.save(const LocalBike(plate: 'ABC1D23', label: 'A'));

      expect(
        () => garage.save(const LocalBike(plate: 'abc1d23', label: 'B')),
        throwsA(isA<DuplicatePlateException>()),
      );
    });

    test('a note ahead of the odometer raises it', () async {
      final garage = LocalGarage(testDatabase());
      await garage.save(
        const LocalBike(plate: 'ABC1D23', label: 'A', mileageKm: 1000),
      );
      final bikeId = garage.bikes.single.id!;

      await garage.saveNote(
        MaintenanceNote(
          bikeId: bikeId,
          doneOn: DateTime(2026, 9, 1),
          description: 'Corrente',
          mileageKm: 4000,
        ),
      );
      await garage.saveNote(
        MaintenanceNote(
          bikeId: bikeId,
          doneOn: DateTime(2026, 8, 1),
          description: 'Óleo',
          mileageKm: 3000,
        ),
      );

      expect(garage.bikes.single.mileageKm, 4000);
      final notes = await garage.notes(bikeId);
      expect(notes.map((n) => n.description), ['Corrente', 'Óleo']);
    });

    test('deleting a bike deletes its notes', () async {
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
    test('keeps a draft with its operations, parts and files', () async {
      final database = testDatabase();
      final outbox = Outbox(database);

      await outbox.add(
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
      final draft = reloaded.drafts.single;
      expect(draft.operations, [
        ServiceOperation.tires,
        ServiceOperation.brakes,
      ]);
      expect(draft.parts.single.name, 'Pneu traseiro');
      expect(draft.attachments.single.bytes, [1, 2, 3]);
      expect(draft.costCents, 24550);

      await reloaded.remove(draft.id!);
      final db = await database.database;
      expect(await db.query('outbox_attachments'), isEmpty);
      expect(await db.query('outbox_parts'), isEmpty);
    });
  });
}
