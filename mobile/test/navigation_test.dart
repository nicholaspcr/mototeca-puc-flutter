import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mototeca/main.dart';
import 'package:mototeca/screens/about_screen.dart';
import 'package:mototeca/screens/customer_portal_screen.dart';
import 'package:mototeca/screens/dashboard_screen.dart';
import 'package:mototeca/screens/login_screen.dart';
import 'package:mototeca/screens/my_vehicles_screen.dart';
import 'package:mototeca/screens/new_record_screen.dart';
import 'package:mototeca/screens/reminders_screen.dart';
import 'package:mototeca/screens/service_detail_screen.dart';
import 'package:mototeca/screens/vehicle_register_screen.dart';
import 'package:mototeca/screens/workshop_register_screen.dart';

/// Mounts the app on a phone-sized surface (393x852 — iPhone 15 Pro).
Future<void> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(const MototecaApp());
  await tester.pumpAndSettle();
}

/// Taps a widget, scrolling it into view first — list children below the fold
/// are not built until the list is scrolled.
Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      240,
      // Text fields carry their own Scrollable — target the page's list.
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 40,
    );
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('abre no Login', (tester) async {
    await pumpApp(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('login como oficina leva ao Painel da Oficina', (tester) async {
    await pumpApp(tester);

    await tapAndSettle(tester, find.byKey(const Key('login-entrar')));

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('login como proprietário leva a Minhas Motos', (tester) async {
    await pumpApp(tester);

    await tapAndSettle(tester, find.byKey(const Key('role-proprietario')));
    await tapAndSettle(tester, find.byKey(const Key('login-entrar')));

    expect(find.byType(MyVehiclesScreen), findsOneWidget);
  });

  testWidgets('login abre o cadastro de oficina e volta ao painel ao salvar', (
    tester,
  ) async {
    await pumpApp(tester);

    await tapAndSettle(
      tester,
      find.byKey(const Key('login-cadastrar-oficina')),
    );
    expect(find.byType(WorkshopRegisterScreen), findsOneWidget);

    await tapAndSettle(
      tester,
      find.byKey(const Key('cadastro-oficina-salvar')),
    );
    expect(find.byType(DashboardScreen), findsOneWidget);
  });

  testWidgets('login abre a consulta pública sem cadastro', (tester) async {
    await pumpApp(tester);

    await tapAndSettle(tester, find.byKey(const Key('login-consulta')));

    expect(find.byType(CustomerPortalScreen), findsOneWidget);
  });

  testWidgets('login abre a tela Sobre o App', (tester) async {
    await pumpApp(tester);

    await tapAndSettle(tester, find.byKey(const Key('login-sobre')));

    expect(find.byType(AboutScreen), findsOneWidget);
  });

  testWidgets('painel abre o Novo Registro e volta ao salvar', (tester) async {
    await pumpApp(tester);
    await tapAndSettle(tester, find.byKey(const Key('login-entrar')));

    await tapAndSettle(
      tester,
      find.byKey(const Key('dashboard-criar-registro')),
    );
    expect(find.byType(NewRecordScreen), findsOneWidget);

    // A busca precisa resolver antes de o formulário (e o botão salvar) aparecer.
    await tapAndSettle(tester, find.byKey(const Key('novo-registro-buscar')));
    await tapAndSettle(tester, find.byKey(const Key('novo-registro-salvar')));

    expect(find.byType(DashboardScreen), findsOneWidget);
  });

  testWidgets('painel abre o cadastro de veículo', (tester) async {
    await pumpApp(tester);
    await tapAndSettle(tester, find.byKey(const Key('login-entrar')));

    await tapAndSettle(
      tester,
      find.byKey(const Key('dashboard-cadastrar-veiculo')),
    );

    expect(find.byType(VehicleRegisterScreen), findsOneWidget);
  });

  testWidgets('painel abre o detalhe de um serviço registrado', (tester) async {
    await pumpApp(tester);
    await tapAndSettle(tester, find.byKey(const Key('login-entrar')));

    await tapAndSettle(tester, find.byKey(const Key('record-r1')));

    expect(find.byType(ServiceDetailScreen), findsOneWidget);
    expect(find.text('Oficina do Zé'), findsWidgets);
  });

  testWidgets('minhas motos abre os lembretes', (tester) async {
    await pumpApp(tester);
    await tapAndSettle(tester, find.byKey(const Key('role-proprietario')));
    await tapAndSettle(tester, find.byKey(const Key('login-entrar')));

    await tapAndSettle(tester, find.byKey(const Key('minhas-motos-lembretes')));

    expect(find.byType(RemindersScreen), findsOneWidget);
  });

  testWidgets('consulta por placa lista o histórico e abre um serviço', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapAndSettle(tester, find.byKey(const Key('login-consulta')));

    await tester.enterText(find.byType(TextField).first, 'ABC1D23');
    await tapAndSettle(tester, find.byKey(const Key('portal-consultar')));

    expect(find.text('Histórico de Serviços'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('history-r1')));
    expect(find.byType(ServiceDetailScreen), findsOneWidget);
  });

  testWidgets('voltar do detalhe retorna à tela anterior', (tester) async {
    await pumpApp(tester);
    await tapAndSettle(tester, find.byKey(const Key('login-entrar')));
    await tapAndSettle(tester, find.byKey(const Key('record-r1')));

    await tapAndSettle(tester, find.byType(BackButton));

    expect(find.byType(DashboardScreen), findsOneWidget);
  });

  testWidgets('sair volta ao Login', (tester) async {
    await pumpApp(tester);
    await tapAndSettle(tester, find.byKey(const Key('login-entrar')));

    await tapAndSettle(tester, find.text('Sair'));

    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
