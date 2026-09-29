# Mototeca — cliente Flutter

Dois aplicativos, um codebase. Nenhum dos dois abre numa tela de login: a raiz
de cada um é uma tela inicial com o que já funciona sem conta e sem sinal.

| | App Motociclista | App Oficina |
|---|---|---|
| Entry point | `lib/main_rider.dart` | `lib/main_shop.dart` |
| Raiz `/` | `rider/rider_home_screen.dart` | `shop/shop_home_screen.dart` |
| Funciona sem conta | garagem, lembretes, notas locais | novo registro, fila de envio |
| Entrar serve para | sincronizar a garagem | publicar a fila no histórico |
| Android | `--flavor rider` | `--flavor shop` |

Telas, rotas e fluxos: [`../design/NAVIGATION.md`](../design/NAVIGATION.md).
Decisões de arquitetura: [`../ARCHITECTURE.md`](../ARCHITECTURE.md) §5.

## Rodar

```bash
flutter run -d chrome -t lib/main_rider.dart    # app do motociclista
flutter run -d chrome -t lib/main_shop.dart     # app da oficina
flutter run --flavor shop -t lib/main_shop.dart # aparelho Android
```

Sem `--dart-define=MOTOTECA_API_URL`, o app usa o backend de demonstração
embutido e não abre conexão nenhuma. Roteiro da apresentação: [`DEMO.md`](DEMO.md).

## Estrutura

```
lib/
  main_rider.dart, main_shop.dart   entry points dos dois apps
  app/         MaterialApp, flavor e tabela de rotas por app
  rider/       telas só do app Motociclista
  shop/        telas só do app Oficina
  shared/      telas compiladas nos dois (consulta, detalhe, veículo, sobre)
  storage/     garagem e fila de envio guardadas no aparelho
  state/       AppState (sessão, repositórios, stores) e AppScope
  repositories/, models/, api/      camada de acesso à API Connect-RPC
  widgets/, theme.dart              design system (tokens em design/README.md)
  demo/        backend de demonstração em memória
  reports/     geração do PDF do histórico
```

Uma tela pertence a `shared/` só quando os dois apps a constroem sem diferença.
Quando o layout precisa mudar por perfil, são duas telas — não um `if` no meio
de uma.

## Testes

```bash
flutter test
```

- `navigation_test.dart` — os dois apps, rota a rota, contra `FakeApi`.
- `demo_flow_test.dart` — os fluxos da apresentação contra o backend embutido.
- `contract_test.dart` — modelos contra JSON capturado da API real
  (`test/fixtures/`).
- `api_test.dart`, `history_pdf_test.dart` — cliente HTTP e PDF.
