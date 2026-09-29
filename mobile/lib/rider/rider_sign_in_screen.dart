import 'package:flutter/material.dart';

import '../app/routes.dart';
import '../demo/demo_backend.dart';
import '../demo/demo_client.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import '../widgets/feedback.dart';
import '../widgets/mt_widgets.dart';

/// Entrar — pushed from the home screen, never the root
/// (design/OwnerLogin.dc.html).
class RiderSignInScreen extends StatefulWidget {
  const RiderSignInScreen({super.key});

  @override
  State<RiderSignInScreen> createState() => _RiderSignInScreenState();
}

class _RiderSignInScreenState extends State<RiderSignInScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final state = AppScope.read(context);
      final session = await state.owners.login(
        phone: _phone.text,
        password: _password.text,
      );
      if (!mounted) return;
      state.signInAsOwner(session);
      Navigator.pushReplacementNamed(context, Routes.garage);
    } catch (error) {
      if (!mounted) return;
      showApiError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bikes = AppScope.of(context).garage.length;

    return Scaffold(
      appBar: const MtAppBar(title: 'Entrar'),
      body: ListView(
        padding: const EdgeInsets.all(MtSizes.screenPadding),
        children: [
          const Text(
            'Confirme seu celular',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.55,
            ),
          ),
          const SizedBox(height: 6),
          const MtFootnote(
            'O número é o que liga você à moto quando uma oficina registra '
            'um serviço.',
          ),
          const SizedBox(height: 18),
          MtCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                MtField(
                  label: 'Celular',
                  hint: '(31) 90000-0000',
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 14),
                MtField(
                  label: 'Senha',
                  hint: 'Sua senha',
                  obscure: true,
                  controller: _password,
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  key: const Key('entrar-confirmar'),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Entrar'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  key: const Key('entrar-cadastrar'),
                  onPressed: () =>
                      Navigator.pushNamed(context, Routes.signUp),
                  child: const Text(
                    'Não tem conta? Cadastre-se',
                    style: TextStyle(color: MtColors.rust),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          MtCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'O que muda depois de entrar',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                MtFootnote(
                  bikes == 0
                      ? 'Suas motos passam a ser guardadas na conta, com os '
                            'serviços que as oficinas registraram.'
                      : 'As $bikes ${bikes == 1 ? 'moto' : 'motos'} deste '
                            'aparelho sobem para a sua conta. Nada é apagado '
                            'se você desistir.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            key: const Key('entrar-sem-conta'),
            onPressed: () => Navigator.pop(context),
            child: const Text('Continuar sem conta'),
          ),
          if (demoMode) ...[
            const SizedBox(height: 14),
            const MtFootnote(
              'Modo demonstração: toque em Entrar com os campos vazios. '
              'Para digitar: celular $demoPhone · senha $demoPassword.',
              align: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
