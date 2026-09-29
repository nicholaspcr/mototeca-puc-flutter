# Navegação entre telas

Mapa de telas e rotas dos apps Flutter. As telas são os artboards em `design/`
(393×852); o mockup ao vivo está em
https://claude.ai/code/artifact/d6cc8a70-1503-4f85-ac17-220bb3a631cc.

A Mototeca é entregue como **dois aplicativos**, porque os dois perfis não
compartilham rotina: o motociclista abre o app algumas vezes por ano, a oficina
abre dezenas de vezes por dia. Um app só obrigava a escolher um perfil antes de
ver qualquer coisa, e essa escolha virava uma tela de login na raiz.

**Regra comum aos dois apps:** a rota `/` é uma tela inicial com o que já dá
para usar, nunca um login. Entrar é uma ação dentro do app, em `/entrar`, e
serve para sincronizar (motociclista) ou publicar (oficina).

## App Motociclista

| Rota | Tela | Artboard | Acesso |
|---|---|---|---|
| `/` | Início | `Main.dc.html` | público, offline |
| `/entrar` | Entrar | `OwnerLogin.dc.html` | público |
| `/cadastro` | Criar Conta | — | público |
| `/garagem` | Minha Garagem | `MyVehicles.dc.html` | offline; sincroniza com conta |
| `/veiculo/cadastro` | Cadastrar Veículo | `VehicleRegister.dc.html` | offline; reivindicar exige conta |
| `/lembretes` | Lembretes | `Reminders.dc.html` | offline |
| `/consulta` | Consultar Placa | `CustomerPortal.dc.html` | público, exige rede |
| `/servico/:id` | Detalhe do Serviço | `ServiceDetail.dc.html` | público, exige rede |
| `/sobre` | Sobre o App | `About.dc.html` | offline |

```
/  --+--> /garagem     --+--> /veiculo/cadastro
     |                   +--> /servico/:id
     +--> /lembretes
     +--> /consulta    ----> /servico/:id
     +--> /entrar      --(entrou)--> /garagem  (a garagem local sobe para a conta)
     +--> /sobre
```

## App Oficina

| Rota | Tela | Artboard | Acesso |
|---|---|---|---|
| `/` | Início | `ShopHome.dc.html` | público, offline |
| `/entrar` | Entrar | `ShopLogin.dc.html` | público |
| `/cadastro` | Cadastrar Oficina | `WorkshopRegister.dc.html` | público |
| `/registro/novo` | Novo Registro | `NewRecord.dc.html` | offline; publicar exige conta |
| `/fila` | Fila de Envio | `Outbox.dc.html` | offline |
| `/painel` | Painel da Oficina | `Dashboard.dc.html` | oficina |
| `/registro/corrigir` | Corrigir Registro | `ReviseRecord.dc.html` | oficina (dona do registro) |
| `/veiculo/cadastro` | Cadastrar Veículo | `VehicleRegister.dc.html` | oficina |
| `/consulta` | Consultar Placa | `CustomerPortal.dc.html` | público, exige rede |
| `/servico/:id` | Detalhe do Serviço | `ServiceDetail.dc.html` | público, exige rede |
| `/sobre` | Sobre o App | `About.dc.html` | offline |

```
/  --+--> /registro/novo --(salvar)--> /fila
     +--> /fila          --(entrar)--> /entrar --(entrou)--> /painel (a fila sobe sozinha)
     +--> /consulta      ----> /servico/:id
     +--> /entrar        --(entrou)--> /painel
     +--> /cadastro      --(criar conta)--> /painel
     +--> /sobre

/painel --+--> /registro/novo
          +--> /veiculo/cadastro
          +--> /servico/:id --> /registro/corrigir
```

## Regras de navegação

A raiz nunca é um formulário. `/` lista o que funciona sem conta e mostra um
botão "Entrar"; quem nunca vai criar conta usa o app inteiro sem passar por
`/entrar`.

`/entrar` é empilhado sobre a tela de origem e volta para ela com
`Navigator.pop`, levando junto o estado que já existia — a garagem local vira
garagem sincronizada, a fila de envio começa a subir. Nada é apagado se o
usuário desistir de entrar.

As telas que concluem um cadastro ou um registro usam `pushReplacement`, para
não empilhar formulários já salvos. O botão voltar do topo usa `Navigator.pop`.

Dois apps, um histórico: `/consulta` e `/servico/:id` existem nos dois e leem os
mesmos dados públicos. São as únicas rotas que exigem rede sem exigir conta.
