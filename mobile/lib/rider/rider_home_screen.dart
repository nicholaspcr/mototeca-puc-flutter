import 'package:flutter/material.dart';

import '../app/flavor.dart';
import '../app/routes.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import '../widgets/mt_widgets.dart';

/// Início — the root of the Motociclista app (design/Main.dc.html).
/// Everything listed here runs on device data.
class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppScope.read(context).garage.load();
  }

  void _onAction() {
    final state = AppScope.read(context);
    if (state.isSignedIn) {
      state.signOut();
      return;
    }
    Navigator.pushNamed(context, Routes.signIn);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final flavor = AppFlavorScope.of(context);
    final signedIn = state.owner != null;

    return Scaffold(
      appBar: MtHomeHeader(
        status: signedIn
            ? 'Olá, ${state.owner?.name ?? 'proprietário'}'
            : 'Sem conta · suas motos ficam salvas neste aparelho',
        actionLabel: signedIn ? 'Sair' : 'Entrar',
        onAction: _onAction,
      ),
      body: ListenableBuilder(
        listenable: state.garage,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(MtSizes.screenPadding),
          children: [
            const Text(
              'O que dá para fazer agora',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            const MtFootnote(
              'Sem cadastro e sem esperar conexão. Entrar é opcional e só '
              'serve para sincronizar.',
            ),
            const SizedBox(height: 16),
            MtFeatureCard(
              key: const Key('inicio-garagem'),
              icon: Icons.two_wheeler_outlined,
              title: 'Minha garagem',
              subtitle: _garageSubtitle(state),
              onTap: () => Navigator.pushNamed(context, Routes.garage),
            ),
            const SizedBox(height: 12),
            MtFeatureCard(
              key: const Key('inicio-lembretes'),
              icon: Icons.notifications_none,
              title: 'Lembretes de manutenção',
              subtitle: 'Troca de óleo e revisões, pela quilometragem',
              onTap: () => Navigator.pushNamed(context, Routes.reminders),
            ),
            const SizedBox(height: 12),
            MtFeatureCard(
              key: const Key('inicio-consulta'),
              icon: Icons.search,
              title: 'Consultar placa',
              subtitle: 'Histórico público de qualquer moto, sem cadastro',
              needsNetwork: true,
              onTap: () => Navigator.pushNamed(context, Routes.plateLookup),
            ),
            const SizedBox(height: 16),
            if (!signedIn) _signInCard(),
            const SizedBox(height: 16),
            MtFootnote(
              'É oficina? Use o app ${flavor.otherApp} para registrar serviços.',
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

  String _garageSubtitle(AppState state) {
    final count = state.garage.length;
    if (count == 0) return 'Nenhuma moto ainda — cadastre a primeira';
    final bike = state.garage.bikes.first;
    return '$count ${count == 1 ? 'moto salva' : 'motos salvas'} neste '
        'aparelho · ${bike.label}';
  }

  Widget _signInCard() {
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
            'Entrar deixa a Mototeca completa',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: MtColors.slate50,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'A conta liga este aparelho ao histórico que as oficinas escrevem.',
            style: TextStyle(
              fontSize: 13,
              color: MtColors.petrolBorder,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          for (final benefit in const [
            'Reivindicar a moto como sua',
            'Ver os serviços registrados pelas oficinas',
            'Guardar no servidor o que já está neste aparelho',
          ]) ...[
            _benefit(benefit),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
          ElevatedButton(
            key: const Key('inicio-entrar'),
            onPressed: () => Navigator.pushNamed(context, Routes.signIn),
            style: ElevatedButton.styleFrom(
              backgroundColor: MtColors.slate50,
              foregroundColor: MtColors.petrol,
            ),
            child: const Text('Entrar ou criar conta'),
          ),
        ],
      ),
    );
  }

  Widget _benefit(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 7),
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: MtColors.rust,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: MtColors.slate50,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}
