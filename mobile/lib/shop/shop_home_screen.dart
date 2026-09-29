import 'package:flutter/material.dart';

import '../app/flavor.dart';
import '../app/routes.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import '../widgets/mt_widgets.dart';

/// Início — the root of the Oficina app (design/ShopHome.dc.html).
/// A record is filled with no signal or account; publishing needs both.
class ShopHomeScreen extends StatefulWidget {
  const ShopHomeScreen({super.key});

  @override
  State<ShopHomeScreen> createState() => _ShopHomeScreenState();
}

class _ShopHomeScreenState extends State<ShopHomeScreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppScope.read(context).outbox.load();
  }

  void _onAction() {
    final state = AppScope.read(context);
    if (state.isSignedIn) {
      state.signOut();
      return;
    }
    Navigator.pushNamed(context, Routes.signIn);
  }

  Future<void> _openNewRecord() async {
    await Navigator.pushNamed(context, Routes.newRecord);
    if (!mounted) return;
    final state = AppScope.read(context);
    if (state.workshop != null) Navigator.pushNamed(context, Routes.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final flavor = AppFlavorScope.of(context);
    final signedIn = state.workshop != null;

    return Scaffold(
      appBar: MtHomeHeader(
        status: signedIn
            ? 'Bem-vindo, ${state.workshop?.name ?? 'oficina'}'
            : 'Sem conta · registros salvos no aparelho',
        actionLabel: signedIn ? 'Sair' : 'Entrar',
        onAction: _onAction,
      ),
      body: ListenableBuilder(
        listenable: state.outbox,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(MtSizes.screenPadding),
          children: [
            _newRecordCard(),
            const SizedBox(height: 20),
            const Text(
              'Também funciona sem entrar',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            const MtFootnote(
              'A conta da oficina só é exigida para publicar o registro no '
              'histórico da moto.',
            ),
            const SizedBox(height: 16),
            MtFeatureCard(
              key: const Key('inicio-fila'),
              icon: Icons.outbox_outlined,
              title: 'Fila de envio',
              subtitle: _outboxSubtitle(state),
              onTap: () => Navigator.pushNamed(context, Routes.outbox),
            ),
            const SizedBox(height: 12),
            MtFeatureCard(
              key: const Key('inicio-consulta'),
              icon: Icons.search,
              title: 'Consultar placa',
              subtitle: 'Veja o que outras oficinas já fizeram na moto',
              needsNetwork: true,
              onTap: () => Navigator.pushNamed(context, Routes.plateLookup),
            ),
            const SizedBox(height: 12),
            if (signedIn)
              MtFeatureCard(
                key: const Key('inicio-painel'),
                icon: Icons.dashboard_outlined,
                title: 'Painel da oficina',
                subtitle: 'Registros do mês e histórico da sua oficina',
                needsNetwork: true,
                onTap: () => Navigator.pushNamed(context, Routes.dashboard),
              )
            else
              _signInCard(),
            const SizedBox(height: 16),
            MtFootnote(
              'É dono da moto? Use o app ${flavor.otherApp}.',
              align: TextAlign.center,
            ),
            TextButton(
              key: const Key('inicio-sobre'),
              onPressed: () => Navigator.pushNamed(context, Routes.about),
              child: const Text(
                'Sobre o app',
                style: TextStyle(color: MtColors.slate500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _outboxSubtitle(AppState state) {
    final count = state.outbox.length;
    if (count == 0) return 'Nada aguardando envio';
    final oldest = state.outbox.drafts.first;
    return '$count ${count == 1 ? 'registro aguardando' : 'registros '
              'aguardando'} · mais antigo de ${oldest.plate}';
  }

  Widget _newRecordCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MtColors.petrol,
        borderRadius: BorderRadius.circular(MtSizes.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Novo Registro',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: MtColors.slate50,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Preencha ao lado da moto, no box. O envio espera o sinal.',
            style: TextStyle(
              fontSize: 13,
              color: MtColors.petrolBorder,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            key: const Key('inicio-novo-registro'),
            onPressed: _openNewRecord,
            style: ElevatedButton.styleFrom(
              backgroundColor: MtColors.slate50,
              foregroundColor: MtColors.petrol,
            ),
            child: const Text('Começar registro'),
          ),
        ],
      ),
    );
  }

  Widget _signInCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MtColors.petrolTint,
        border: Border.all(color: MtColors.petrolBorder),
        borderRadius: BorderRadius.circular(MtSizes.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Entrar para publicar',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: MtColors.petrol,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Um registro só entra no histórico público assinado pelo CNPJ da '
            'oficina. Entre uma vez e a fila sobe sozinha.',
            style: TextStyle(
              fontSize: 13,
              color: MtColors.petrol,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            key: const Key('inicio-entrar'),
            onPressed: () => Navigator.pushNamed(context, Routes.signIn),
            child: const Text('Entrar com CNPJ'),
          ),
        ],
      ),
    );
  }
}
