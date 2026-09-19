import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mototeca/api/api_client.dart';
import 'package:mototeca/demo/demo_backend.dart';
import 'package:mototeca/demo/demo_client.dart';
import 'package:mototeca/main.dart';
import 'package:mototeca/screens/dashboard_screen.dart';
import 'package:mototeca/screens/my_vehicles_screen.dart';
import 'package:mototeca/screens/service_detail_screen.dart';
import 'package:mototeca/state/app_scope.dart';

import 'navigation_test.dart' show enterInField, tapAndSettle;

/// The class demo runs with no backend at all: these drive the real screens
/// against the in-app data, so every workflow shown on the day is covered.
Future<void> pumpDemoApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final state = AppState(
    client: ApiClient(
      baseUrl: 'demo://mototeca',
      httpClient: DemoClient(backend: DemoBackend(), latency: Duration.zero),
    ),
  );
  await tester.pumpWidget(MototecaApp(state: state));
  await tester.pumpAndSettle();
}

Future<void> signIn(WidgetTester tester, {required bool asOwner}) async {
  if (asOwner) {
    await tapAndSettle(tester, find.byKey(const Key('role-proprietario')));
  }
  await tester.enterText(
    find.byType(TextField).first,
    asOwner ? demoPhone : demoCNPJ,
  );
  await tester.enterText(find.byType(TextField).at(1), demoPassword);
  await tapAndSettle(tester, find.byKey(const Key('login-entrar')));
}

void main() {
  testWidgets('oficina entra e vê o histórico semeado', (tester) async {
    await pumpDemoApp(tester);
    await signIn(tester, asOwner: false);

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.textContaining('Oficina do Zé'), findsWidgets);
    expect(find.textContaining(demoPlate), findsWidgets);
  });

  // On stage "Entrar" should be one tap, with nothing typed.
  testWidgets('entrar com os campos vazios abre cada perfil', (tester) async {
    await pumpDemoApp(tester);
    await tapAndSettle(tester, find.byKey(const Key('login-entrar')));
    expect(find.byType(DashboardScreen), findsOneWidget);

    await tapAndSettle(tester, find.text('Sair'));
    await tapAndSettle(tester, find.byKey(const Key('role-proprietario')));
    await tapAndSettle(tester, find.byKey(const Key('login-entrar')));
    expect(find.byType(MyVehiclesScreen), findsOneWidget);
  });

  testWidgets('oficina lança um registro que aparece no painel', (
    tester,
  ) async {
    await pumpDemoApp(tester);
    await signIn(tester, asOwner: false);

    await tapAndSettle(
      tester,
      find.byKey(const Key('dashboard-criar-registro')),
    );
    await tester.enterText(find.byType(TextField).first, demoPlate);
    await tapAndSettle(tester, find.byKey(const Key('novo-registro-buscar')));
    await tapAndSettle(tester, find.text('Pneus'));
    await enterInField(tester, const Key('novo-registro-km'), '19200');
    await tapAndSettle(tester, find.byKey(const Key('novo-registro-salvar')));

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.textContaining('19200 km'), findsWidgets);
  });

  testWidgets('quilometragem menor que a última pede confirmação', (
    tester,
  ) async {
    await pumpDemoApp(tester);
    await signIn(tester, asOwner: false);

    await tapAndSettle(
      tester,
      find.byKey(const Key('dashboard-criar-registro')),
    );
    await tester.enterText(find.byType(TextField).first, demoPlate);
    await tapAndSettle(tester, find.byKey(const Key('novo-registro-buscar')));
    await tapAndSettle(tester, find.text('Pneus'));
    await enterInField(tester, const Key('novo-registro-km'), '5000');
    await tapAndSettle(tester, find.byKey(const Key('novo-registro-salvar')));

    expect(find.text('Quilometragem menor'), findsOneWidget);
    await tapAndSettle(
      tester,
      find.byKey(const Key('novo-registro-confirmar-km')),
    );
    expect(find.byType(DashboardScreen), findsOneWidget);
  });

  testWidgets('oficina corrige o próprio registro', (tester) async {
    await pumpDemoApp(tester);
    await signIn(tester, asOwner: false);

    final firstRecord = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('record-'),
    );
    await tapAndSettle(tester, firstRecord.first);
    expect(find.byType(ServiceDetailScreen), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('detalhe-corrigir')));
    await tester.scrollUntilVisible(
      find.byKey(const Key('novo-registro-km')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await enterInField(tester, const Key('novo-registro-km'), '18500');
    await tapAndSettle(tester, find.byKey(const Key('novo-registro-salvar')));

    expect(find.text('Correção de um registro anterior'), findsOneWidget);
  });

  testWidgets('consulta pública mostra o histórico das duas oficinas', (
    tester,
  ) async {
    await pumpDemoApp(tester);

    await tapAndSettle(tester, find.byKey(const Key('login-consulta')));
    await tester.enterText(find.byType(TextField).first, demoPlate);
    await tapAndSettle(tester, find.byKey(const Key('portal-consultar')));

    expect(find.text('Histórico de Serviços'), findsOneWidget);
    expect(find.textContaining('Oficina do Zé'), findsWidgets);
    expect(find.textContaining('Moto Center BH'), findsWidgets);
  });

  testWidgets('proprietário vincula e desvincula uma moto', (tester) async {
    await pumpDemoApp(tester);
    await signIn(tester, asOwner: true);

    expect(find.byType(MyVehiclesScreen), findsOneWidget);
    expect(find.textContaining('KLM3C45'), findsWidgets);

    await tapAndSettle(tester, find.byKey(const Key('minhas-motos-cadastrar')));
    await enterInField(tester, const Key('adicionar-moto-placa'), demoPlate);
    await enterInField(
      tester,
      const Key('adicionar-moto-chassi'),
      demoChassi.substring(demoChassi.length - 6),
    );
    await tapAndSettle(
      tester,
      find.byKey(const Key('adicionar-moto-continuar')),
    );

    expect(find.textContaining(demoPlate), findsWidgets);

    await tapAndSettle(tester, find.byKey(Key('vehicle-menu-$demoPlate')));
    await tapAndSettle(tester, find.byKey(const Key('vehicle-release')));
    await tapAndSettle(
      tester,
      find.byKey(const Key('vehicle-release-confirmar')),
    );

    expect(find.text('Moto desvinculada.'), findsOneWidget);
  });

  testWidgets('final do chassi errado é recusado', (tester) async {
    await pumpDemoApp(tester);
    await signIn(tester, asOwner: true);

    await tapAndSettle(tester, find.byKey(const Key('minhas-motos-cadastrar')));
    await enterInField(tester, const Key('adicionar-moto-placa'), demoPlate);
    await enterInField(tester, const Key('adicionar-moto-chassi'), '999999');
    await tapAndSettle(
      tester,
      find.byKey(const Key('adicionar-moto-continuar')),
    );

    expect(
      find.text('o final do chassi não confere com esta placa'),
      findsOneWidget,
    );
  });
}
