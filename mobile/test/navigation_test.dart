import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mototeca/app/app.dart';
import 'package:mototeca/app/flavor.dart';
import 'package:mototeca/rider/garage_screen.dart';
import 'package:mototeca/rider/owner_register_screen.dart';
import 'package:mototeca/rider/reminders_screen.dart';
import 'package:mototeca/rider/rider_home_screen.dart';
import 'package:mototeca/rider/rider_sign_in_screen.dart';
import 'package:mototeca/shared/about_screen.dart';
import 'package:mototeca/shared/plate_lookup_screen.dart';
import 'package:mototeca/shared/service_detail_screen.dart';
import 'package:mototeca/shared/vehicle_register_screen.dart';
import 'package:mototeca/shop/dashboard_screen.dart';
import 'package:mototeca/shop/new_record_screen.dart';
import 'package:mototeca/shop/outbox_screen.dart';
import 'package:mototeca/shop/shop_home_screen.dart';
import 'package:mototeca/shop/shop_sign_in_screen.dart';
import 'package:mototeca/shop/workshop_register_screen.dart';

import 'fake_api.dart';

/// Mounts one of the two apps on a phone-sized surface (393x852 — iPhone 15
/// Pro), backed by [FakeApi] so the screens run their real network code.
Future<FakeApi> pumpApp(WidgetTester tester, AppFlavor flavor) async {
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final api = FakeApi();
  // A fresh key per pump, so a test that mounts both apps really remounts.
  await tester.pumpWidget(
    MototecaApp(key: ValueKey(flavor), flavor: flavor, state: api.state),
  );
  await tester.pumpAndSettle();
  return api;
}

Future<FakeApi> pumpRiderApp(WidgetTester tester) =>
    pumpApp(tester, AppFlavor.rider);

Future<FakeApi> pumpShopApp(WidgetTester tester) =>
    pumpApp(tester, AppFlavor.shop);

/// Signs in from the rider home, the way the screen offers it.
Future<void> signInAsOwner(WidgetTester tester) async {
  await tapAndSettle(tester, find.byKey(const Key('inicio-entrar')));
  await tester.enterText(find.byType(TextField).first, '(31) 99000-1234');
  await tester.enterText(find.byType(TextField).at(1), 'senha-forte-123');
  await tapAndSettle(tester, find.byKey(const Key('entrar-confirmar')));
}

/// Signs in from the workshop home.
Future<void> signInAsWorkshop(WidgetTester tester) async {
  await tapAndSettle(tester, find.byKey(const Key('inicio-entrar')));
  await tester.enterText(find.byType(TextField).first, '11.222.333/0001-81');
  await tester.enterText(find.byType(TextField).at(1), 'senha-forte-123');
  await tapAndSettle(tester, find.byKey(const Key('entrar-confirmar')));
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
  group('App Motociclista', () {
    testWidgets('abre no Início, não num login', (tester) async {
      await pumpRiderApp(tester);

      expect(find.byType(RiderHomeScreen), findsOneWidget);
      expect(find.byType(RiderSignInScreen), findsNothing);
      expect(find.text('O que dá para fazer agora'), findsOneWidget);
    });

    testWidgets('abre a garagem sem conta', (tester) async {
      final api = await pumpRiderApp(tester);

      await tapAndSettle(tester, find.byKey(const Key('inicio-garagem')));

      expect(find.byType(GarageScreen), findsOneWidget);
      expect(
        api.calls,
        isNot(contains('mototeca.owner.v1.OwnerService/ListMyVehicles')),
        reason: 'signed out the garage never calls the server',
      );
    });

    testWidgets('guarda uma moto no aparelho sem conta', (tester) async {
      final api = await pumpRiderApp(tester);
      await tapAndSettle(tester, find.byKey(const Key('inicio-garagem')));

      await tapAndSettle(tester, find.byKey(const Key('garagem-adicionar')));
      await enterInField(tester, const Key('adicionar-moto-placa'), 'abc1d23');
      await enterInField(
        tester,
        const Key('adicionar-moto-modelo'),
        'Honda CG 160 Start',
      );
      await enterInField(tester, const Key('adicionar-moto-km'), '18420');
      await tapAndSettle(
        tester,
        find.byKey(const Key('adicionar-moto-continuar')),
      );

      expect(find.text('Só neste aparelho'), findsOneWidget);
      expect(find.text('Honda CG 160 Start'), findsOneWidget);
      final stored = await api.store.read('garage');
      expect((stored?['bikes'] as List).single, containsPair('plate', 'ABC1D23'));
    });

    testWidgets('entrar leva à garagem sincronizada', (tester) async {
      await pumpRiderApp(tester);

      await signInAsOwner(tester);

      expect(find.byType(GarageScreen), findsOneWidget);
      expect(find.text('Sincronizada'), findsOneWidget);
    });

    testWidgets('entrar abre o cadastro do proprietário', (tester) async {
      await pumpRiderApp(tester);
      await tapAndSettle(tester, find.byKey(const Key('inicio-entrar')));

      await tapAndSettle(tester, find.byKey(const Key('entrar-cadastrar')));

      expect(find.byType(OwnerRegisterScreen), findsOneWidget);
    });

    testWidgets('continuar sem conta volta ao Início', (tester) async {
      await pumpRiderApp(tester);
      await tapAndSettle(tester, find.byKey(const Key('inicio-entrar')));

      await tapAndSettle(tester, find.byKey(const Key('entrar-sem-conta')));

      expect(find.byType(RiderHomeScreen), findsOneWidget);
    });

    testWidgets('garagem abre os lembretes', (tester) async {
      await pumpRiderApp(tester);
      await signInAsOwner(tester);

      await tapAndSettle(tester, find.byKey(const Key('garagem-lembretes')));

      expect(find.byType(RemindersScreen), findsOneWidget);
    });

    // A bike a workshop already registered is claimed straight away, with its
    // history — the owner never retypes the chassi.
    testWidgets('vincula uma moto já cadastrada pela placa', (tester) async {
      final api = await pumpRiderApp(tester);
      await signInAsOwner(tester);

      await tapAndSettle(tester, find.byKey(const Key('garagem-adicionar')));
      await enterInField(tester, const Key('adicionar-moto-placa'), 'abc-1d23');
      await enterInField(tester, const Key('adicionar-moto-chassi'), '000001');
      await tapAndSettle(
        tester,
        find.byKey(const Key('adicionar-moto-continuar')),
      );

      expect(find.byType(GarageScreen), findsOneWidget);
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

    testWidgets('cadastra e vincula uma placa desconhecida', (tester) async {
      final api = await pumpRiderApp(tester);
      await signInAsOwner(tester);
      const claim = 'mototeca.owner.v1.OwnerService/ClaimVehicle';
      api.failures[claim] = (
        status: 404,
        code: 'not_found',
        message: 'nenhuma moto cadastrada com esta placa',
      );

      await tapAndSettle(tester, find.byKey(const Key('garagem-adicionar')));
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

      expect(find.byType(GarageScreen), findsOneWidget);
      expect(
        api.calls.where((c) => c == claim).length,
        2,
        reason: 'claims once, registers, then claims the new bike',
      );
      expect(api.lastBody[claim]?['chassiSuffix'], '000001');
    });

    testWidgets('desvincula uma moto vendida', (tester) async {
      final api = await pumpRiderApp(tester);
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
  });

  group('App Oficina', () {
    testWidgets('abre no Início, não num login', (tester) async {
      await pumpShopApp(tester);

      expect(find.byType(ShopHomeScreen), findsOneWidget);
      expect(find.byType(ShopSignInScreen), findsNothing);
      expect(find.text('Novo Registro'), findsOneWidget);
    });

    testWidgets('entrar leva ao Painel da Oficina', (tester) async {
      await pumpShopApp(tester);

      await signInAsWorkshop(tester);

      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.byType(ShopSignInScreen), findsNothing);
    });

    testWidgets('entrar abre o cadastro da oficina e vai ao painel', (
      tester,
    ) async {
      await pumpShopApp(tester);
      await tapAndSettle(tester, find.byKey(const Key('inicio-entrar')));

      await tapAndSettle(tester, find.byKey(const Key('entrar-cadastrar')));
      expect(find.byType(WorkshopRegisterScreen), findsOneWidget);

      await tapAndSettle(
        tester,
        find.byKey(const Key('cadastro-oficina-salvar')),
      );
      expect(find.byType(DashboardScreen), findsOneWidget);
    });

    testWidgets('registro sem conta vai para a fila do aparelho', (
      tester,
    ) async {
      final api = await pumpShopApp(tester);

      await tapAndSettle(
        tester,
        find.byKey(const Key('inicio-novo-registro')),
      );
      expect(find.byType(NewRecordScreen), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'ABC1D23');
      await enterInField(
        tester,
        const Key('novo-registro-modelo'),
        'Honda CG 160 Start',
      );
      await tapAndSettle(tester, find.text('Pneus'));
      await enterInField(tester, const Key('novo-registro-km'), '18500');
      await tapAndSettle(tester, find.byKey(const Key('novo-registro-salvar')));

      expect(find.byType(ShopHomeScreen), findsOneWidget);
      expect(
        api.calls,
        isNot(
          contains(
            'mototeca.service.v1.ServiceRecordService/CreateServiceRecord',
          ),
        ),
        reason: 'nothing is published before the workshop signs in',
      );

      await tapAndSettle(tester, find.byKey(const Key('inicio-fila')));
      expect(find.byType(OutboxScreen), findsOneWidget);
      expect(find.text('Aguardando conta'), findsOneWidget);
    });

    testWidgets('entrar publica a fila guardada no aparelho', (tester) async {
      final api = await pumpShopApp(tester);
      await tapAndSettle(
        tester,
        find.byKey(const Key('inicio-novo-registro')),
      );
      await tester.enterText(find.byType(TextField).first, 'ABC1D23');
      await tapAndSettle(tester, find.text('Pneus'));
      await enterInField(tester, const Key('novo-registro-km'), '18500');
      await tapAndSettle(tester, find.byKey(const Key('novo-registro-salvar')));

      await signInAsWorkshop(tester);

      const create =
          'mototeca.service.v1.ServiceRecordService/CreateServiceRecord';
      expect(api.lastBody[create]?['plate'], 'ABC1D23');
      expect(api.lastBody[create]?['mileageKm'], 18500);
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.text('Tudo enviado'), findsOneWidget);
    });

    testWidgets('painel abre o Novo Registro e volta ao salvar', (
      tester,
    ) async {
      await pumpShopApp(tester);
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
      final api = await pumpShopApp(tester);
      await signInAsWorkshop(tester);
      const create =
          'mototeca.service.v1.ServiceRecordService/CreateServiceRecord';
      api.failures[create] = (
        status: 400,
        code: 'failed_precondition',
        message:
            'quilometragem menor que a última registrada para esta moto '
            '(18999 km)',
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
      await pumpShopApp(tester);
      await signInAsWorkshop(tester);

      await tapAndSettle(
        tester,
        find.byKey(const Key('dashboard-cadastrar-veiculo')),
      );

      expect(find.byType(VehicleRegisterScreen), findsOneWidget);
    });

    testWidgets('painel abre o detalhe de um serviço registrado', (
      tester,
    ) async {
      await pumpShopApp(tester);
      await signInAsWorkshop(tester);

      await tapAndSettle(tester, find.byKey(const Key('record-r1')));

      expect(find.byType(ServiceDetailScreen), findsOneWidget);
      expect(find.text('Oficina do Zé'), findsWidgets);
    });

    testWidgets('corrige um registro a partir do detalhe', (tester) async {
      final api = await pumpShopApp(tester);
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

    testWidgets('detalhe abre todas as fotos de uma etapa', (tester) async {
      final api = await pumpShopApp(tester);
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
      await pumpShopApp(tester);
      await signInAsWorkshop(tester);
      await tapAndSettle(tester, find.byKey(const Key('record-r1')));

      await tapAndSettle(tester, find.byType(BackButton));

      expect(find.byType(DashboardScreen), findsOneWidget);
    });
  });

  group('Comum aos dois apps', () {
    testWidgets('consulta por placa sem cadastro, nos dois apps', (
      tester,
    ) async {
      for (final flavor in AppFlavor.values) {
        await pumpApp(tester, flavor);

        await tapAndSettle(tester, find.byKey(const Key('inicio-consulta')));
        expect(find.byType(PlateLookupScreen), findsOneWidget);

        await tester.enterText(find.byType(TextField).first, 'ABC1D23');
        await tapAndSettle(tester, find.byKey(const Key('portal-consultar')));
        expect(find.text('Histórico de Serviços'), findsOneWidget);

        await tapAndSettle(tester, find.byKey(const Key('history-r1')));
        expect(find.byType(ServiceDetailScreen), findsOneWidget);
      }
    });

    testWidgets('início abre a tela Sobre o App', (tester) async {
      for (final flavor in AppFlavor.values) {
        await pumpApp(tester, flavor);

        await tapAndSettle(tester, find.byKey(const Key('inicio-sobre')));

        expect(find.byType(AboutScreen), findsOneWidget);
      }
    });

    testWidgets('registro corrigido leva à correção', (tester) async {
      final api = await pumpRiderApp(tester);
      api.responses['mototeca.service.v1.ServiceRecordService/ListServiceRecordsByPlate'] =
          {
            'vehicle': FakeApi.vehicleSummaryJson,
            'records': [
              {...FakeApi.recordJson, 'supersededByRecordId': 'r2'},
            ],
          };
      await tapAndSettle(tester, find.byKey(const Key('inicio-consulta')));
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
        api
            .lastBody['mototeca.service.v1.ServiceRecordService/GetServiceRecord'],
        {'id': 'r2'},
      );
      expect(
        find.text('Este registro foi corrigido pela oficina.'),
        findsNothing,
      );
    });

    // A 12h token can expire while the app is open. Home still works signed
    // out, so that is where the user lands.
    testWidgets('sessão expirada volta ao Início', (tester) async {
      final api = await pumpShopApp(tester);
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

      expect(find.byType(ShopHomeScreen), findsOneWidget);
      expect(find.byType(DashboardScreen), findsNothing);
    });

    testWidgets('sair volta ao Início e o app continua usável', (tester) async {
      await pumpShopApp(tester);
      await signInAsWorkshop(tester);

      await tapAndSettle(tester, find.byType(BackButton));
      await tapAndSettle(tester, find.text('Sair'));

      expect(find.byType(ShopHomeScreen), findsOneWidget);
      expect(find.byKey(const Key('inicio-novo-registro')), findsOneWidget);
    });
  });
}
