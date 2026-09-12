# Navegação entre telas

Mapa de telas e rotas do app Flutter. As telas são os artboards em `design/` (393×852); o mockup ao vivo está em https://claude.ai/code/artifact/d6cc8a70-1503-4f85-ac17-220bb3a631cc.

## Rotas

| Rota | Tela | Artboard | Acesso |
|---|---|---|---|
| `/` | Login | `Main.dc.html` | público |
| `/oficina/cadastro` | Cadastrar Oficina | `WorkshopRegister.dc.html` | público |
| `/oficina` | Painel da Oficina | `Dashboard.dc.html` | oficina |
| `/oficina/registro/novo` | Novo Registro | `NewRecord.dc.html` | oficina |
| `/veiculo/cadastro` | Cadastrar Veículo | `VehicleRegister.dc.html` | oficina, proprietário |
| `/proprietario` | Minhas Motos | `MyVehicles.dc.html` | proprietário |
| `/proprietario/lembretes` | Lembretes | `Reminders.dc.html` | proprietário |
| `/consulta` | Portal do Proprietário | `CustomerPortal.dc.html` | público |
| `/servico/:id` | Detalhe do Serviço | `ServiceDetail.dc.html` | público (via histórico) |
| `/sobre` | Sobre o App | `About.dc.html` | público |

## Fluxos

**Oficina (mecânico)** — o perfil de alta frequência, que alimenta o histórico:

```
/  --(entrar como oficina)-->  /oficina  --+--> /oficina/registro/novo --(salvar)--> /oficina
                                           +--> /veiculo/cadastro      --(salvar)--> /oficina
                                           +--> /servico/:id           --(voltar)--> /oficina
/  --(cadastre sua oficina)-->  /oficina/cadastro  --(criar conta)-->  /oficina
```

**Proprietário** — perfil de baixa frequência, só leitura do histórico:

```
/  --(entrar como proprietário)-->  /proprietario  --+--> /proprietario/lembretes
                                                     +--> /veiculo/cadastro
                                                     +--> /servico/:id
```

**Consulta pública** — sem conta, o diferencial do produto:

```
/  --(consultar sem cadastro)-->  /consulta  --(buscar placa)-->  /consulta (histórico)  -->  /servico/:id
```

**Comum aos dois perfis:** `/sobre` é alcançável a partir de `/`, e o botão "Sair" em `/oficina` e `/proprietario` volta para `/` limpando a sessão.

## Regras de navegação

O login é a única raiz: o perfil escolhido (`oficina` ou `proprietário`) decide o destino após entrar, e não existe navegação cruzada entre os dois fluxos sem passar por `/`. O botão voltar do topo usa `Navigator.pop`, enquanto as ações que concluem um cadastro ou registro usam `pushReplacement` para não empilhar formulários já salvos.

`/consulta` e `/servico/:id` são as únicas rotas que funcionam sem sessão — é o que sustenta a regra do produto de consultar histórico por placa sem criar conta.
