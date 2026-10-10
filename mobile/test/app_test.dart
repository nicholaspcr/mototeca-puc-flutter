import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mototeca/api/api_client.dart';
import 'package:mototeca/app/app.dart';
import 'package:mototeca/app/flavor.dart';
import 'package:mototeca/demo/demo_backend.dart';
import 'package:mototeca/demo/demo_client.dart';
import 'package:mototeca/models/service_operation.dart';
import 'package:mototeca/shop/dashboard_screen.dart';
import 'package:mototeca/state/app_scope.dart';
import 'package:mototeca/storage/garage_store.dart';
import 'package:mototeca/storage/outbox_store.dart';

import 'test_database.dart';

/// Mounts one app on a phone-sized screen, with an empty device database and
/// the in-app demo server, exactly as the class demo runs.
Future<AppState> pumpApp(WidgetTester tester, AppFlavor flavor) async {
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final state = AppState(
    client: ApiClient(
      baseUrl: 'demo://mototeca',
      httpClient: DemoClient(backend: DemoBackend(), latency: Duration.zero),
    ),
    database: testDatabase(),
  );
  await tester.pumpWidget(MototecaApp(flavor: flavor, state: state));
  await tester.pumpAndSettle();
  return state;
}

/// Blank fields sign in as the demo account.
Future<void> signIn(WidgetTester tester) async {
  await tap(tester, find.byKey(const Key('inicio-entrar')));
  await tap(tester, find.byKey(const Key('entrar-confirmar')));
}

Future<void> type(WidgetTester tester, String key, String text) async {
  await reveal(tester, find.byKey(Key(key)));
  await tester.enterText(
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField)),
    text,
  );
  await tester.pumpAndSettle();
}

/// Lists build only what is on screen, so scroll until the target exists.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      240,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> addBike(WidgetTester tester, String plate, String label) async {
  await tap(tester, find.byKey(const Key('garagem-adicionar')));
  await type(tester, 'adicionar-moto-placa', plate);
  await type(tester, 'adicionar-moto-modelo', label);
  await type(tester, 'adicionar-moto-km', '18420');
  await tap(tester, find.byKey(const Key('adicionar-moto-continuar')));
}

void expectMessage(String text) => expect(find.text(text), findsOneWidget);

void main() {
  group('Motociclista, sem conta', () {
    testWidgets('salva a moto e recusa placa inválida ou repetida', (
      tester,
    ) async {
      final state = await pumpApp(tester, AppFlavor.rider);
      await tap(tester, find.byKey(const Key('inicio-garagem')));

      await addBike(tester, 'abc1d23', 'Honda CG 160');
      expectMessage('Moto salva neste aparelho.');

      await addBike(tester, 'AB12', 'Outra');
      expectMessage('Placa inválida. Use ABC1234 ou ABC1D23.');
      await tap(tester, find.text('Cancelar'));

      await addBike(tester, 'ABC1D23', 'Outra');
      expectMessage('A moto ABC1D23 já está na garagem.');

      expect(state.garage.bikes.map((b) => b.label), ['Honda CG 160']);
    });

    testWidgets('anotação sobe o hodômetro; editar e apagar', (tester) async {
      final state = await pumpApp(tester, AppFlavor.rider);
      await state.garage.save(
        const LocalBike(plate: 'ABC1D23', label: 'Honda CG', mileageKm: 100),
      );
      await tap(tester, find.byKey(const Key('inicio-garagem')));
      await tap(tester, find.byKey(const Key('vehicle-ABC1D23')));

      await tap(tester, find.byKey(const Key('anotacao-nova')));
      await tap(tester, find.byKey(const Key('anotacao-salvar')));
      expectMessage('Descreva o que foi feito.');
      await type(tester, 'anotacao-descricao', 'Troca de óleo');
      await type(tester, 'anotacao-km', '3000');
      await type(tester, 'anotacao-valor', '45,00');
      await tap(tester, find.byKey(const Key('anotacao-salvar')));
      expectMessage('Anotação salva.');
      expect(find.textContaining('3000 km'), findsWidgets);

      await tap(tester, find.text('Troca de óleo'));
      await type(tester, 'anotacao-descricao', 'Óleo 10W30');
      await tap(tester, find.byKey(const Key('anotacao-salvar')));
      expectMessage('Anotação atualizada.');

      await tester.longPress(find.text('Óleo 10W30'));
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('anotacao-apagar-confirmar')));
      expectMessage('Anotação apagada.');
      expect(state.garage.bikes.single.mileageKm, 3000);
    });

    testWidgets('editar e remover a moto', (tester) async {
      final state = await pumpApp(tester, AppFlavor.rider);
      await state.garage.save(
        const LocalBike(plate: 'ABC1D23', label: 'Honda CG', mileageKm: 100),
      );
      await tap(tester, find.byKey(const Key('inicio-garagem')));

      await tap(tester, find.byKey(const Key('vehicle-menu-ABC1D23')));
      await tap(tester, find.byKey(const Key('vehicle-edit')));
      await type(tester, 'adicionar-moto-km', '2500');
      await tap(tester, find.byKey(const Key('adicionar-moto-continuar')));
      expectMessage('Moto atualizada.');
      expect(state.garage.bikes.single.mileageKm, 2500);

      await tap(tester, find.byKey(const Key('vehicle-menu-ABC1D23')));
      await tap(tester, find.byKey(const Key('vehicle-release')));
      await tap(tester, find.byKey(const Key('vehicle-release-confirmar')));
      expectMessage('Moto removida deste aparelho.');
      expect(state.garage.isEmpty, isTrue);
    });
  });

  testWidgets('Motociclista com conta: final do chassi errado é recusado', (
    tester,
  ) async {
    await pumpApp(tester, AppFlavor.rider);
    await signIn(tester);

    await tap(tester, find.byKey(const Key('garagem-adicionar')));
    await type(tester, 'adicionar-moto-placa', demoPlate);
    await type(tester, 'adicionar-moto-chassi', '999999');
    await tap(tester, find.byKey(const Key('adicionar-moto-continuar')));
    expectMessage('o final do chassi não confere com esta placa');

    await tap(tester, find.byKey(const Key('garagem-adicionar')));
    await type(tester, 'adicionar-moto-placa', demoPlate);
    await type(tester, 'adicionar-moto-chassi', demoChassi.substring(11));
    await tap(tester, find.byKey(const Key('adicionar-moto-continuar')));
    expectMessage('Moto vinculada.');
  });

  group('Oficina', () {
    testWidgets('sem conta o registro fica na fila e pode ser descartado', (
      tester,
    ) async {
      final state = await pumpApp(tester, AppFlavor.shop);

      await tap(tester, find.byKey(const Key('inicio-novo-registro')));
      await tester.enterText(find.byType(TextField).first, demoPlate);
      await type(tester, 'novo-registro-km', '18500');
      await tap(tester, find.byKey(const Key('novo-registro-salvar')));
      expectMessage('Selecione ao menos uma operação.');

      await tester.scrollUntilVisible(
        find.text('Pneus'),
        -240,
        scrollable: find.byType(Scrollable).first,
      );
      await tap(tester, find.text('Pneus'));
      await tap(tester, find.byKey(const Key('novo-registro-salvar')));
      expectMessage('Registro salvo na fila de envio.');

      await tap(tester, find.byKey(const Key('inicio-fila')));
      expect(find.text('Aguardando conta'), findsOneWidget);
      final id = state.outbox.drafts.single.id;
      await tap(tester, find.byKey(Key('fila-descartar-$id')));
      await tap(tester, find.byKey(const Key('fila-descartar-confirmar')));
      expectMessage('Registro descartado.');
      expect(state.outbox.isEmpty, isTrue);
    });

    testWidgets('entrar publica o aceito e mantém o recusado na fila', (
      tester,
    ) async {
      final state = await pumpApp(tester, AppFlavor.shop);
      for (final plate in [demoPlate, 'XYZ9A99']) {
        await state.outbox.add(
          OutboxDraft(
            plate: plate,
            vehicleLabel: 'Moto',
            operations: const [ServiceOperation.tires],
            mileageKm: 99000,
            savedAt: DateTime(2026, 10, 10),
          ),
        );
      }

      await signIn(tester);

      expectMessage(
        'Publicados: 1 registro. Não subiram: 1 registro. Continuam na fila.',
      );
      expect(state.outbox.drafts.single.plate, 'XYZ9A99');
    });

    testWidgets('quilometragem menor que a última pede confirmação', (
      tester,
    ) async {
      await pumpApp(tester, AppFlavor.shop);
      await signIn(tester);

      await tap(tester, find.byKey(const Key('dashboard-criar-registro')));
      await tester.enterText(find.byType(TextField).first, demoPlate);
      await tap(tester, find.byKey(const Key('novo-registro-buscar')));
      await tap(tester, find.text('Pneus'));
      await type(tester, 'novo-registro-km', '5000');
      await tap(tester, find.byKey(const Key('novo-registro-salvar')));

      expect(find.text('Quilometragem menor'), findsOneWidget);
      await tap(tester, find.byKey(const Key('novo-registro-confirmar-km')));
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.textContaining('5000 km'), findsWidgets);
    });

    testWidgets('um registro publicado só muda por correção', (tester) async {
      await pumpApp(tester, AppFlavor.shop);
      await signIn(tester);

      final record = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('record-'),
      );
      await tap(tester, record.first);
      await tap(tester, find.byKey(const Key('detalhe-corrigir')));
      await type(tester, 'novo-registro-km', '18500');
      await tap(tester, find.byKey(const Key('novo-registro-salvar')));

      expect(find.text('Correção de um registro anterior'), findsOneWidget);
    });
  });

  testWidgets('consulta pública mostra o histórico de todas as oficinas', (
    tester,
  ) async {
    await pumpApp(tester, AppFlavor.rider);

    await tap(tester, find.byKey(const Key('inicio-consulta')));
    await tester.enterText(find.byType(TextField).first, demoPlate);
    await tap(tester, find.byKey(const Key('portal-consultar')));

    expect(find.textContaining('Oficina do Zé'), findsWidgets);
    expect(find.textContaining('Moto Center BH'), findsWidgets);
  });
}
