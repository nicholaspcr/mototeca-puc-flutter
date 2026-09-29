import 'package:flutter/material.dart';

import '../main.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import '../widgets/feedback.dart';
import '../widgets/mt_widgets.dart';

/// Cadastro do proprietário. No CPF: reading your own history doesn't need
/// one, and collecting it anyway is personal data with no use (§8).
class OwnerRegisterScreen extends StatefulWidget {
  const OwnerRegisterScreen({super.key});

  @override
  State<OwnerRegisterScreen> createState() => _OwnerRegisterScreenState();
}

class _OwnerRegisterScreenState extends State<OwnerRegisterScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final state = AppScope.read(context);
      final session = await state.owners.createOwner(
        name: _name.text,
        phone: _phone.text,
        password: _password.text,
      );
      if (!mounted) return;
      state.signInAsOwner(session);
      Navigator.pushReplacementNamed(context, Routes.myVehicles);
    } catch (error) {
      if (!mounted) return;
      showApiError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Criar Conta')),
      body: ListView(
        padding: const EdgeInsets.all(MtSizes.screenPadding),
        children: [
          const MtFootnote(
            'Crie sua conta para acompanhar o histórico e os lembretes das '
            'suas motos. Consultar o histórico de uma placa continua não '
            'exigindo cadastro.',
          ),
          const SizedBox(height: 16),
          MtCard(
            child: Column(
              children: [
                MtField(
                  label: 'Nome',
                  hint: 'Seu nome completo',
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 14),
                MtField(
                  label: 'Celular',
                  hint: '(31) 90000-0000',
                  helper: 'Com DDD',
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 14),
                MtField(
                  label: 'Senha',
                  hint: 'Mínimo de 8 caracteres',
                  obscure: true,
                  controller: _password,
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  key: const Key('cadastro-proprietario-salvar'),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Criar Conta'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Já tem conta? Entrar',
                style: TextStyle(color: MtColors.rust),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
