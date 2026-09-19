# Como demonstrar o app em aula

App Flutter com navegação funcional entre as 10 telas. Rotas em
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
flutter run -d chrome
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
flutter run -d <id-do-aparelho>   # celular em modo desenvolvedor, via USB
```

## Credenciais da demonstração

Aparecem no rodapé da tela de Login, então não precisa decorar:

| | |
|---|---|
| Oficina | CNPJ `11222333000181` · senha `senha-forte-123` |
| Proprietário | celular `31990001234` · senha `senha-forte-123` |
| Moto de exemplo | placa `ABC1D23` · final do chassi `000001` |

## Roteiro sugerido (3 minutos)

Mostra os dois perfis e a consulta pública, que é o diferencial do produto:

1. **Entrar como oficina** (CNPJ e senha acima) → Painel da Oficina, com os
   serviços já registrados e o contador do mês.
   (Ou **Cadastre sua oficina** para mostrar o cadastro: CNPJ válido, nome e
   senha de 8+ caracteres.)
2. **Criar Registro** → busca a placa `ABC1D23` → seleciona duas operações →
   preenche km (acima de 18.420), valor e uma peça → toca em **Fotos antes**
   (dá para escolher várias) e em **Foto da nota fiscal** → **Salvar
   Registro**. Volta ao painel com o registro novo no topo.
3. Toca no **registro recente** → Detalhe do Serviço (peças, observações,
   fotos — toque para ver todas —, nota fiscal) → **Corrigir registro** →
   muda a quilometragem → **Salvar Correção**. O detalhe passa a mostrar a
   correção; o original fica preservado.
4. **Sair** → **Consultar sem cadastro** → digita `ABC1D23` → **Consultar** →
   o histórico aparece sem login, com serviços de **duas oficinas diferentes**.
   É o argumento central do produto. **Baixar PDF** gera o histórico em PDF.
5. **Sair** → "Sou proprietário" → entra com o celular acima → **Minhas Motos**
   já traz a Yamaha Factor com quilometragem, serviços e o aviso de troca de
   óleo. (Ou **Cadastre-se** para mostrar o cadastro do proprietário.)
6. **+ Cadastrar nova moto** → placa `ABC1D23` e final do chassi `000001` (os
   6 últimos caracteres, que estão no documento da moto) → **Continuar** → a
   moto entra na lista com todo o histórico das oficinas.
7. **Lembretes de manutenção** → a barra e o aviso saem da própria
   quilometragem: 3.000 km desde a última troca de óleo.
8. Menu **⋮** da moto → **Vendi esta moto** → **Desvincular**: o histórico
   continua com a placa para o próximo dono.

### Erros que valem mostrar

São as mesmas respostas que o backend dá — o modo demonstração aplica as
mesmas regras:

- Senha errada no login → *"CNPJ ou senha inválidos"* (a mesma mensagem para
  CNPJ inexistente, de propósito: não dá para descobrir quais oficinas
  existem).
- Salvar um registro sem escolher operação → *"selecione ao menos uma
  operação"*.
- Lançar um registro com quilometragem menor que a última → o app pergunta se
  o painel foi trocado antes de salvar. É o sinal de hodômetro adulterado.
- Vincular com o final do chassi errado → *"o final do chassi não confere com
  esta placa"*.
- Buscar uma placa não cadastrada no Novo Registro → oferece cadastrar o
  veículo antes.

## Rodando contra o backend de verdade (opcional)

Não é necessário para a apresentação. Quando quiser exercitar a API Go:

```bash
cd mototeca
docker compose up -d     # Postgres, migrations, MinIO e a API em :8080
make e2e                  # popula dados e confere todos os endpoints

cd mobile
flutter run -d chrome --dart-define=MOTOTECA_API_URL=http://localhost:8080
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
