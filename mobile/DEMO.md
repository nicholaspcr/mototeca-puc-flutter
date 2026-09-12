# Como demonstrar o app em aula

App Flutter com navegação funcional entre as 10 telas. Rotas em [`../design/NAVIGATION.md`](../design/NAVIGATION.md).

O Flutter está em `~/.develop/flutter/bin` — se `flutter` não for encontrado, rode antes:

```bash
export PATH="$HOME/.develop/flutter/bin:$PATH"
```

## Opção 1 — Chrome, ao vivo (recomendada)

```bash
cd mototeca/mobile
flutter run -d chrome
```

Abre o app no Chrome em ~30s. É o app real rodando, com hot reload (tecla `r`) se precisar mexer em algo na hora. O app já se desenha com largura de celular (393 pt) e fundo cinza em volta, então fica com cara de telefone no projetor sem precisar do DevTools.

**Ponto fraco:** compila na hora. Se a aula for corrida, use a opção 2.

## Opção 2 — Build pronto, sem esperar compilação

Antes da aula:

```bash
cd mototeca/mobile
flutter build web --release
```

Na aula (abre instantâneo, funciona sem internet):

```bash
cd mototeca/mobile/build/web && python3 -m http.server 8080
```

Depois abra `http://localhost:8080`.

## Opção 3 — Celular de verdade

Precisa do Android SDK, que **não está instalado** nesta máquina. Se quiser essa opção, instale o Android Studio, rode `flutter doctor` até o item Android ficar ✓, e então:

```bash
flutter run -d <id-do-aparelho>   # com o celular no modo desenvolvedor, via USB
```

Não é necessário para a entrega — a navegação funcional pode ser demonstrada no Chrome.

## Roteiro sugerido (2 minutos)

Mostra os dois perfis e a consulta pública, que é o diferencial do produto:

1. **Login** → "Sou da oficina" → **Entrar** → Painel da Oficina.
2. **Criar Registro** → busca a placa `ABC1D23` → veículo aparece → seleciona operações → **Salvar Registro** (volta ao painel).
3. No painel, toca em um **registro recente** → Detalhe do Serviço (peças, fotos, nota fiscal) → voltar.
4. **Sair** → no login, escolhe "Sou proprietário" → **Entrar** → Minhas Motos.
5. **Lembretes de manutenção** → mostra o aviso por km.
6. **Sair** → **Consultar sem cadastro** → digita `ABC1D23` → **Consultar** → histórico entre oficinas diferentes.

Placas que existem nos dados de exemplo: `ABC1D23`, `BRA2E19`.

## Se quiser provar que a navegação está testada

```bash
cd mototeca/mobile
flutter test
```

13 testes de navegação — cada um toca num botão e verifica se a tela de destino abriu.
