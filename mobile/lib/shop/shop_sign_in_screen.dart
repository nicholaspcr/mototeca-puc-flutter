import 'package:flutter/material.dart';

import '../app/routes.dart';
import '../demo/demo_backend.dart';
import '../demo/demo_client.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import '../widgets/feedback.dart';
import '../widgets/mt_widgets.dart';

/// Entrar — pushed from the home screen, never the root
/// (design/ShopLogin.dc.html).
class ShopSignInScreen extends StatefulWidget {
  const ShopSignInScreen({super.key});

  @override
  State<ShopSignInScreen> createState() => _ShopSignInScreenState();
}

class _ShopSignInScreenState extends State<ShopSignInScreen> {
  final _cnpj = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _cnpj.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final state = AppScope.read(context);
      final session = await state.workshops.login(
        cnpj: _cnpj.text,
        password: _password.text,
      );
      if (!mounted) return;
      state.signIn(session);

      // Signing in is what the queue was waiting for.
      final flushed = await state.outbox.flush(state.serviceRecords);
      if (!mounted) return;
      if (flushed.sent > 0) {
        showSuccess(
          context,
          '${flushed.sent} registro(s) da fila publicados.',
        );
      }
      Navigator.pushReplacementNamed(context, Routes.dashboard);
    } catch (error) {
      if (!mounted) return;
      showApiError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final queued = AppScope.of(context).outbox.length;

    return Scaffold(
      appBar: const MtAppBar(title: 'Entrar'),
      body: ListView(
        padding: const EdgeInsets.all(MtSizes.screenPadding),
        children: [
          const Text(
            'Conta da oficina',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.55,
            ),
          ),
          const SizedBox(height: 6),
          const MtFootnote(
            'Cada registro publicado leva o CNPJ que o assinou. É isso que dá '
            'valor ao histórico.',
          ),
          const SizedBox(height: 18),
          MtCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                MtField(
                  label: 'CNPJ da oficina',
                  hint: '00.000.000/0001-00',
                  mono: true,
                  controller: _cnpj,
                  keyboardType: TextInputType.number,
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
                    'Não tem conta? Cadastre sua oficina',
                    style: TextStyle(color: MtColors.rust),
                  ),
                ),
              ],
            ),
          ),
          if (queued > 0) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: MtColors.petrolTint,
                border: Border.all(color: MtColors.petrolBorder),
                borderRadius: BorderRadius.circular(MtSizes.cardRadius),
              ),
              child: Text(
                'Ao entrar, os $queued registros que estão na fila deste '
                'aparelho são enviados em segundo plano.',
                style: const TextStyle(
                  fontSize: 13,
                  color: MtColors.petrol,
                  height: 1.5,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          OutlinedButton(
            key: const Key('entrar-sem-conta'),
            onPressed: () => Navigator.pop(context),
            child: const Text('Voltar e continuar offline'),
          ),
          if (demoMode) ...[
            const SizedBox(height: 14),
            const MtFootnote(
              'Modo demonstração: toque em Entrar com os campos vazios. '
              'Para digitar: CNPJ $demoCNPJ · senha $demoPassword.',
              align: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
