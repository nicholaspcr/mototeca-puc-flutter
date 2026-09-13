# Como demonstrar o app em aula

App Flutter com navegação funcional entre as 10 telas, falando com a API Go
real. Rotas em [`../design/NAVIGATION.md`](../design/NAVIGATION.md).

O Flutter está em `~/.develop/flutter/bin` — se `flutter` não for encontrado,
rode antes:

```bash
export PATH="$HOME/.develop/flutter/bin:$PATH"
```

## Antes de tudo: subir o backend

O fluxo da oficina e a consulta por placa gravam e leem do banco de verdade, ou
seja, precisam da API no ar. O jeito mais curto é o Docker:

```bash
cd mototeca
docker compose up -d          # sobe Postgres, aplica as migrations, MinIO e a API em :8080
```

> Se o banco foi criado antes do controle de migrations, o serviço `migrate`
> para com *"database predates migration tracking"*. Recrie-o com
> `docker compose down -v` (apaga os dados locais) e suba de novo.

Confira com `curl -s localhost:8080/healthz -o /dev/null -w '%{http_code}\n'`
— deve responder `200`.

Para popular dados de exemplo (uma oficina, uma moto e um serviço), rode
`make e2e`: ele confere a resposta de todos os endpoints e deixa o banco com
conteúdo para a demonstração. Entre duas execuções, espere uns 30 segundos — o
último passo esgota de propósito o limite de tentativas de login.

> Todas as telas usam a API — não sobrou nenhum dado de exemplo no app. O
> login do proprietário é celular + senha; o código por WhatsApp continua sendo
> o desenho final, mas depende de um provedor de SMS que o backend não tem.

## Opção 1 — Chrome, ao vivo (recomendada)

```bash
cd mototeca/mobile
flutter run -d chrome
```

Abre o app no Chrome em ~30s, com hot reload (tecla `r`). O app já se desenha
com largura de celular (393 pt) e fundo cinza em volta, então fica com cara de
telefone no projetor sem precisar do DevTools. A API aceita chamadas de
qualquer origem `localhost`, que é de onde o Chrome serve o app.

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

Cuidado: a API também usa a 8080. Suba o servidor estático em outra porta
(`python3 -m http.server 8081`) ou aponte o app para outro endereço com
`--dart-define=MOTOTECA_API_URL=http://localhost:8080` no momento do build.

## Opção 3 — Celular de verdade

Precisa do Android SDK, que **não está instalado** nesta máquina. Se quiser
essa opção, instale o Android Studio, rode `flutter doctor` até o item Android
ficar ✓, e então:

```bash
flutter run -d <id-do-aparelho>   # celular em modo desenvolvedor, via USB
```

Num aparelho físico o `localhost` é o próprio celular, então aponte para o IP
da máquina:

```bash
flutter run -d <id> --dart-define=MOTOTECA_API_URL=http://192.168.0.10:8080
```

No emulador Android, o host é `http://10.0.2.2:8080`.

## Roteiro sugerido (3 minutos)

Mostra os dois perfis e a consulta pública, que é o diferencial do produto:

1. **Cadastrar oficina** → CNPJ `11.222.333/0001-81`, nome, senha (mín. 8
   caracteres) → cai direto no Painel da Oficina, já autenticado.
   (Se já rodou `make e2e`, esse CNPJ existe: entre com a senha
   `senha-forte-123`.)
2. No painel, **Cadastrar veículo** → placa `ABC1D23`, chassi de 17 caracteres,
   marca, modelo, ano.
3. **Criar Registro** → busca a placa → seleciona duas operações → preenche km,
   valor e uma peça → toca em **Foto antes** e em **Foto da nota fiscal** e
   escolhe imagens → **Salvar Registro**. Volta ao painel e o contador do mês
   sobe. (Os arquivos sobem depois do registro: precisam dele para se anexar.)
4. Toca no **registro recente** → Detalhe do Serviço (peças, observações,
   fotos, nota fiscal — **Baixar** abre a imagem) → voltar.
5. **Sair** → **Consultar sem cadastro** → digita `ABC1D23` → **Consultar** →
   o mesmo serviço aparece, sem login. É o argumento central do produto.
   **Baixar PDF** gera o histórico em PDF no próprio aparelho.
6. **Sair** → "Sou proprietário" → **Cadastre-se** → nome, celular
   `(31) 99000-1234`, senha → cai em Minhas Motos (vazio no começo).
   (Se já rodou `make e2e`, esse celular existe: entre com `senha-forte-123`.)
7. **+ Cadastrar nova moto** → digita a placa `ABC1D23` → **Continuar** → como
   a oficina já cadastrou a moto, ela é vinculada direto, com a quilometragem e
   o último serviço do passo 3. Uma placa que ninguém cadastrou abre o
   formulário de cadastro e vincula a moto ao salvar.
8. **Lembretes de manutenção** → a barra e o aviso saem da própria
   quilometragem: 3.000 km desde a última troca de óleo.

### Erros que valem mostrar

São respostas reais do backend, não mensagens de enfeite:

- Senha errada no login → *"CNPJ ou senha inválidos"* (a mesma mensagem para
  CNPJ inexistente, de propósito: não dá para descobrir quais oficinas existem).
- Salvar um registro sem escolher operação → *"selecione ao menos uma operação"*.
- Buscar uma placa não cadastrada no Novo Registro → oferece cadastrar o
  veículo antes.
- Vincular uma moto que já tem dono → *"esta moto já está vinculada a outro
  proprietário"*.

## Se quiser provar que está testado

```bash
cd mototeca/mobile && flutter test   # cliente da API, contrato e navegação
cd mototeca && make test              # backend
cd mototeca && make e2e               # confere a resposta de cada endpoint
```

`test/contract_test.dart` roda contra JSON capturado da API real
(`test/fixtures/`), então prova que os modelos Dart entendem o que o servidor
de fato responde — e não só o que a gente imaginou que ele responde.
