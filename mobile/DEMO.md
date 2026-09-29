# Como demonstrar o app em aula

São **dois apps** Flutter com navegação funcional, um por perfil. Nenhum dos
dois abre numa tela de login. Rotas em
[`../design/NAVIGATION.md`](../design/NAVIGATION.md).

**O app roda sozinho: sem backend, sem banco, sem internet.** Por padrão ele
usa um backend de demonstração embutido (`lib/demo/`), com dados de exemplo já
no aparelho — duas oficinas, duas motos, histórico e um proprietário. Tudo que
você faz na apresentação (cadastrar, lançar registro, corrigir, vincular moto)
vale para a sessão inteira e aparece nas outras telas, como se fosse o servidor
de verdade.

> Recarregar a página zera os dados e volta ao exemplo inicial — útil para
> repetir a demonstração.

O Flutter está em `~/.develop/flutter/bin` — se `flutter` não for encontrado,
rode antes:

```bash
export PATH="$HOME/.develop/flutter/bin:$PATH"
```

## Opção 1 — Chrome, ao vivo (recomendada)

```bash
cd mototeca/mobile
flutter run -d chrome -t lib/main_shop.dart     # app da oficina
flutter run -d chrome -t lib/main_rider.dart    # app do motociclista
```

Abre o app no Chrome em ~30s, com hot reload (tecla `r`). O app já se desenha
com largura de celular (393 pt) e fundo cinza em volta, então fica com cara de
telefone no projetor sem precisar do DevTools.

**Ponto fraco:** compila na hora. Se a aula for corrida, use a opção 2.

## Opção 2 — Build pronto, sem esperar compilação

Antes da aula:

```bash
cd mototeca/mobile
flutter build web --release
```

Na aula:

```bash
cd mototeca/mobile/build/web && python3 -m http.server 8080
```

## Opção 3 — Celular de verdade

Precisa do Android SDK, que **não está instalado** nesta máquina. Se quiser
essa opção, instale o Android Studio, rode `flutter doctor` até o item Android
ficar ✓, e então:

```bash
flutter run --flavor shop  -t lib/main_shop.dart  -d <id-do-aparelho>
flutter run --flavor rider -t lib/main_rider.dart -d <id-do-aparelho>
```

Os dois `applicationId` são diferentes (`.oficina` e `.motociclista`), então os
dois aplicativos ficam instalados lado a lado.

## Entrar

Entrar é opcional: as duas telas iniciais já funcionam sem conta. Quando for a
hora, toque em **Entrar** e **deixe os campos em branco** — o modo demonstração
entra na conta de exemplo, nos dois apps.

Se quiser digitar (ou mostrar o erro de senha), as credenciais aparecem no
rodapé da tela Entrar:

| | |
|---|---|
| Oficina | CNPJ `11222333000181` · senha `senha-forte-123` |
| Proprietário | celular `31990001234` · senha `senha-forte-123` |
| Moto de exemplo | placa `ABC1D23` · final do chassi `000001` |

## Roteiro sugerido (4 minutos)

Mostra os dois apps e a consulta pública, que é o diferencial do produto.

**App Oficina** (`flutter run -d chrome -t lib/main_shop.dart`)

1. A tela inicial abre **sem login**, com o que dá para fazer agora: Novo
   Registro, Fila de envio, Consultar placa.
2. **Começar registro** *sem entrar* → digita a placa `ABC1D23`, o modelo,
   escolhe duas operações, preenche km e valor → **Salvar na fila de envio**.
   Nada foi para o servidor.
3. **Fila de envio** → o registro está lá, marcado *Aguardando conta*.
4. **Entrar e enviar** → campos vazios → **Entrar**: a fila sobe sozinha e o
   Painel da Oficina abre com o registro publicado.
5. Toca no **registro recente** → Detalhe do Serviço → **Corrigir registro** →
   muda a quilometragem → **Salvar Correção**. O original fica preservado.
6. **Consultar placa** → `ABC1D23` → histórico com serviços de **duas oficinas
   diferentes**. É o argumento central do produto. **Baixar PDF** gera o
   histórico em PDF.

**App Motociclista** (`flutter run -d chrome -t lib/main_rider.dart`)

7. A tela inicial lista o que funciona offline, com o selo *Funciona offline*
   em cada item, e *Precisa de internet* só na consulta por placa.
8. **Minha garagem** *sem entrar* → **+ Adicionar moto** → placa, modelo e km
   → a moto entra com o selo **Só neste aparelho**.
9. **Entrar** (campos vazios) → a garagem passa a mostrar as motos da conta,
   com **Sincronizada**, quilometragem, serviços e o aviso de troca de óleo.
10. **+ Adicionar moto** → placa `ABC1D23` e final do chassi `000001` (os 6
    últimos, que estão no CRLV) → a moto entra com o histórico das oficinas.
11. **Lembretes de manutenção** → a barra sai da própria quilometragem: 3.000
    km desde a última troca de óleo.
12. Menu **⋮** da moto → **Vendi esta moto** → **Desvincular**: o histórico
    continua com a placa para o próximo dono.

### Erros que valem mostrar

São as mesmas respostas que o backend dá — o modo demonstração aplica as
mesmas regras:

- Senha errada no login (digitando um CNPJ e uma senha qualquer) → *"CNPJ ou
  senha inválidos"* (a mesma mensagem para CNPJ inexistente, de propósito: não
  dá para descobrir quais oficinas existem).
- Salvar um registro sem escolher operação → *"selecione ao menos uma
  operação"*.
- Lançar um registro com quilometragem menor que a última → o app pergunta se
  o painel foi trocado antes de salvar. É o sinal de hodômetro adulterado.
- Vincular com o final do chassi errado → *"o final do chassi não confere com
  esta placa"*.
- Buscar uma placa não cadastrada no Novo Registro → oferece cadastrar o
  veículo antes.
- Sair da oficina e abrir a fila → *Nada é enviado antes de você entrar*.

## Rodando contra o backend de verdade (opcional)

Não é necessário para a apresentação. Quando quiser exercitar a API Go:

```bash
cd mototeca
docker compose up -d     # Postgres, migrations, MinIO e a API em :8080
make e2e                  # popula dados e confere todos os endpoints

cd mobile
flutter run -d chrome -t lib/main_shop.dart \
  --dart-define=MOTOTECA_API_URL=http://localhost:8080
```

Passar `MOTOTECA_API_URL` desliga o modo demonstração; sem ele o app nunca
abre conexão nenhuma. Para forçar o modo demonstração mesmo com uma URL
definida, use `--dart-define=MOTOTECA_DEMO=true`.

No emulador Android o host é `http://10.0.2.2:8080`; num aparelho físico, o IP
da máquina (`--dart-define=MOTOTECA_API_URL=http://192.168.0.10:8080`).

## Se quiser provar que está testado

```bash
cd mototeca/mobile && flutter test   # inclui test/demo_flow_test.dart, que
                                      # percorre os fluxos da apresentação
cd mototeca && make test              # backend
cd mototeca && make e2e               # confere a resposta de cada endpoint
```

`test/contract_test.dart` roda contra JSON capturado da API real
(`test/fixtures/`), então prova que os modelos Dart entendem o que o servidor
de fato responde — e que o backend de demonstração fala a mesma língua.
