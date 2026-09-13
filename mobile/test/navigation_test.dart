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

import 'fake_api.dart';

/// Mounts the app on a phone-sized surface (393x852 — iPhone 15 Pro), backed
/// by [FakeApi] so the screens run their real network code paths.
Future<FakeApi> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final api = FakeApi();
  await tester.pumpWidget(MototecaApp(state: api.state));
  await tester.pumpAndSettle();
  return api;
}

/// Signs in on the proprietário side.
Future<void> signInAsOwner(WidgetTester tester) async {
  await tapAndSettle(tester, find.byKey(const Key('role-proprietario')));
  await tester.enterText(find.byType(TextField).first, '(31) 99000-1234');
  await tester.enterText(find.byType(TextField).at(1), 'senha-forte-123');
  await tapAndSettle(tester, find.byKey(const Key('login-entrar')));
}

/// Signs in on the oficina side, filling the form the way a user would.
Future<void> signInAsWorkshop(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, '11.222.333/0001-81');
  await tester.enterText(find.byType(TextField).at(1), 'senha-forte-123');
  await tapAndSettle(tester, find.byKey(const Key('login-entrar')));
}

/// Types into the TextField inside a keyed MtField.
Future<void> enterInField(WidgetTester tester, Key key, String text) async {
  await tester.enterText(
    find.descendant(of: find.byKey(key), matching: find.byType(TextField)),
    text,
  );
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

    await signInAsWorkshop(tester);

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('login como proprietário leva a Minhas Motos', (tester) async {
    await pumpApp(tester);

    await signInAsOwner(tester);

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
    await signInAsWorkshop(tester);

    await tapAndSettle(
      tester,
      find.byKey(const Key('dashboard-criar-registro')),
    );
    expect(find.byType(NewRecordScreen), findsOneWidget);

    // O formulário só aparece depois de a placa resolver num veículo.
    await tester.enterText(find.byType(TextField).first, 'ABC1D23');
    await tapAndSettle(tester, find.byKey(const Key('novo-registro-buscar')));

    await tapAndSettle(tester, find.text('Pneus'));
    await enterInField(tester, const Key('novo-registro-km'), '18500');
    await tapAndSettle(tester, find.byKey(const Key('novo-registro-salvar')));

    expect(find.byType(DashboardScreen), findsOneWidget);
  });

  testWidgets('quilometragem menor pede confirmação antes de salvar', (
    tester,
  ) async {
    final api = await pumpApp(tester);
    await signInAsWorkshop(tester);
    const create =
        'mototeca.service.v1.ServiceRecordService/CreateServiceRecord';
    api.failures[create] = (
      status: 400,
      code: 'failed_precondition',
      message: 'quilometragem menor que a última registrada para esta moto (18999 km)',
    );
    api.failOnce.add(create);

    await tapAndSettle(
      tester,
      find.byKey(const Key('dashboard-criar-registro')),
    );
    await tester.enterText(find.byType(TextField).first, 'ABC1D23');
    await tapAndSettle(tester, find.byKey(const Key('novo-registro-buscar')));
    await tapAndSettle(tester, find.text('Pneus'));
    await enterInField(tester, const Key('novo-registro-km'), '1200');
    await tapAndSettle(tester, find.byKey(const Key('novo-registro-salvar')));

    expect(find.text('Quilometragem menor'), findsOneWidget);
    await tapAndSettle(
      tester,
      find.byKey(const Key('novo-registro-confirmar-km')),
    );

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(api.lastBody[create]?['confirmLowerMileage'], isTrue);
  });

  testWidgets('painel abre o cadastro de veículo', (tester) async {
    await pumpApp(tester);
    await signInAsWorkshop(tester);

    await tapAndSettle(
      tester,
      find.byKey(const Key('dashboard-cadastrar-veiculo')),
    );

    expect(find.byType(VehicleRegisterScreen), findsOneWidget);
  });

  testWidgets('painel abre o detalhe de um serviço registrado', (tester) async {
    await pumpApp(tester);
    await signInAsWorkshop(tester);

    await tapAndSettle(tester, find.byKey(const Key('record-r1')));

    expect(find.byType(ServiceDetailScreen), findsOneWidget);
    expect(find.text('Oficina do Zé'), findsWidgets);
  });

  testWidgets('minhas motos abre os lembretes', (tester) async {
    await pumpApp(tester);
    await signInAsOwner(tester);

    await tapAndSettle(tester, find.byKey(const Key('minhas-motos-lembretes')));

    expect(find.byType(RemindersScreen), findsOneWidget);
  });

  // A bike a workshop already registered is claimed straight away, with its
  // history — the owner never retypes the chassi.
  testWidgets('minhas motos vincula uma moto já cadastrada pela placa', (
    tester,
  ) async {
    final api = await pumpApp(tester);
    await signInAsOwner(tester);

    await tapAndSettle(tester, find.byKey(const Key('minhas-motos-cadastrar')));
    await enterInField(tester, const Key('adicionar-moto-placa'), 'abc-1d23');
    await enterInField(tester, const Key('adicionar-moto-chassi'), '000001');
    await tapAndSettle(
      tester,
      find.byKey(const Key('adicionar-moto-continuar')),
    );

    expect(find.byType(MyVehiclesScreen), findsOneWidget);
    expect(find.byType(VehicleRegisterScreen), findsNothing);
    expect(api.lastBody['mototeca.owner.v1.OwnerService/ClaimVehicle'], {
      'plate': 'ABC1D23',
      'chassiSuffix': '000001',
    });
    expect(
      api.calls,
      isNot(contains('mototeca.vehicle.v1.VehicleService/CreateVehicle')),
    );
  });

  testWidgets('minhas motos cadastra e vincula uma placa desconhecida', (
    tester,
  ) async {
    final api = await pumpApp(tester);
    await signInAsOwner(tester);
    const claim = 'mototeca.owner.v1.OwnerService/ClaimVehicle';
    api.failures[claim] = (
      status: 404,
      code: 'not_found',
      message: 'nenhuma moto cadastrada com esta placa',
    );

    await tapAndSettle(tester, find.byKey(const Key('minhas-motos-cadastrar')));
    await enterInField(tester, const Key('adicionar-moto-placa'), 'ABC1D23');
    await enterInField(tester, const Key('adicionar-moto-chassi'), '999999');
    await tapAndSettle(
      tester,
      find.byKey(const Key('adicionar-moto-continuar')),
    );

    expect(find.byType(VehicleRegisterScreen), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      'ABC1D23',
      reason: 'the plate the owner typed carries over',
    );

    api.failures.remove(claim);
    await tester.enterText(find.byType(TextField).at(1), '9C2KC1670GR000001');
    await tester.enterText(find.byType(TextField).at(2), 'Honda');
    await tester.enterText(find.byType(TextField).at(3), 'CG 160 Start');
    await tester.enterText(find.byType(TextField).at(4), '2022');
    await tapAndSettle(
      tester,
      find.byKey(const Key('cadastro-veiculo-salvar')),
    );

    expect(find.byType(MyVehiclesScreen), findsOneWidget);
    expect(
      api.calls.where((c) => c == claim).length,
      2,
      reason: 'claims once, registers, then claims the new bike',
    );
    expect(
      api.lastBody[claim]?['chassiSuffix'],
      '000001',
      reason: 'the second claim uses the chassi just registered',
    );
  });

  testWidgets('minhas motos desvincula uma moto vendida', (tester) async {
    final api = await pumpApp(tester);
    await signInAsOwner(tester);

    await tapAndSettle(tester, find.byKey(const Key('vehicle-menu-ABC1D23')));
    await tapAndSettle(tester, find.byKey(const Key('vehicle-release')));
    expect(find.text('Desvincular moto'), findsOneWidget);
    await tapAndSettle(
      tester,
      find.byKey(const Key('vehicle-release-confirmar')),
    );

    expect(api.lastBody['mototeca.owner.v1.OwnerService/ReleaseVehicle'], {
      'plate': 'ABC1D23',
    });
    expect(find.text('Moto desvinculada.'), findsOneWidget);
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

  testWidgets('oficina corrige um registro a partir do detalhe', (
    tester,
  ) async {
    final api = await pumpApp(tester);
    await signInAsWorkshop(tester);
    await tapAndSettle(tester, find.byKey(const Key('record-r1')));

    await tapAndSettle(tester, find.byKey(const Key('detalhe-corrigir')));
    expect(find.text('Corrigir Registro'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('novo-registro-km')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('novo-registro-km')),
              matching: find.byType(TextField),
            ),
          )
          .controller
          ?.text,
      '18420',
      reason: 'the form starts from the record being corrected',
    );

    await enterInField(tester, const Key('novo-registro-km'), '18500');
    await tapAndSettle(tester, find.byKey(const Key('novo-registro-salvar')));

    const revise =
        'mototeca.service.v1.ServiceRecordService/ReviseServiceRecord';
    expect(api.lastBody[revise]?['recordId'], 'r1');
    expect(api.lastBody[revise]?['mileageKm'], 18500);
    expect(find.byType(ServiceDetailScreen), findsOneWidget);
    expect(find.text('Correção de um registro anterior'), findsOneWidget);

    await tapAndSettle(tester, find.byType(BackButton));
    expect(find.byType(DashboardScreen), findsOneWidget);
  });

  testWidgets('registro corrigido leva à correção', (tester) async {
    final api = await pumpApp(tester);
    api.responses['mototeca.service.v1.ServiceRecordService/ListServiceRecordsByPlate'] =
        {
          'vehicle': FakeApi.vehicleSummaryJson,
          'records': [
            {...FakeApi.recordJson, 'supersededByRecordId': 'r2'},
          ],
        };
    await tapAndSettle(tester, find.byKey(const Key('login-consulta')));
    await tester.enterText(find.byType(TextField).first, 'ABC1D23');
    await tapAndSettle(tester, find.byKey(const Key('portal-consultar')));
    await tapAndSettle(tester, find.byKey(const Key('history-r1')));

    expect(
      find.text('Este registro foi corrigido pela oficina.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('detalhe-corrigir')), findsNothing);

    await tapAndSettle(tester, find.byKey(const Key('detalhe-ver-correcao')));

    expect(
      api.lastBody['mototeca.service.v1.ServiceRecordService/GetServiceRecord'],
      {'id': 'r2'},
    );
    expect(
      find.text('Este registro foi corrigido pela oficina.'),
      findsNothing,
    );
  });

  testWidgets('detalhe abre todas as fotos de uma etapa', (tester) async {
    final api = await pumpApp(tester);
    api.responses['mototeca.service.v1.ServiceRecordService/ListWorkshopServiceRecords'] =
        {
          'countThisMonth': 1,
          'records': [
            {
              ...FakeApi.recordJson,
              'attachments': [
                for (final id in ['a1', 'a2'])
                  {
                    'id': id,
                    'url': 'http://storage/$id.jpg',
                    'kind': 'photo',
                    'phase': 'PHOTO_PHASE_BEFORE',
                  },
              ],
            },
          ],
        };
    await signInAsWorkshop(tester);
    await tapAndSettle(tester, find.byKey(const Key('record-r1')));

    expect(find.text('Antes (2)'), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('detalhe-fotos-Antes')));

    expect(find.text('Antes · 1 de 2'), findsOneWidget);
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Antes · 2 de 2'), findsOneWidget);
  });

  testWidgets('voltar do detalhe retorna à tela anterior', (tester) async {
    await pumpApp(tester);
    await signInAsWorkshop(tester);
    await tapAndSettle(tester, find.byKey(const Key('record-r1')));

    await tapAndSettle(tester, find.byType(BackButton));

    expect(find.byType(DashboardScreen), findsOneWidget);
  });

  // A 12h token can expire while the app is open; the user must land back on
  // login rather than face a screen that only ever errors.
  testWidgets('sessão expirada volta ao Login', (tester) async {
    final api = await pumpApp(tester);
    await signInAsWorkshop(tester);
    expect(find.byType(DashboardScreen), findsOneWidget);

    api.failures['mototeca.service.v1.ServiceRecordService/ListWorkshopServiceRecords'] =
        (
          status: 401,
          code: 'unauthenticated',
          message: 'sessão expirada — entre novamente',
        );

    await tester.fling(
      find.byType(RefreshIndicator),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(DashboardScreen), findsNothing);
  });

  testWidgets('sair volta ao Login', (tester) async {
    await pumpApp(tester);
    await signInAsWorkshop(tester);

    await tapAndSettle(tester, find.text('Sair'));

    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
