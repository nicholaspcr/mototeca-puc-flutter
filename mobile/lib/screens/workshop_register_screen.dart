import 'package:flutter/material.dart';

import '../main.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import '../widgets/feedback.dart';
import '../widgets/mt_widgets.dart';

/// Cadastrar Oficina — CNPJ-verified onboarding (ARCHITECTURE.md §6).
class WorkshopRegisterScreen extends StatefulWidget {
  const WorkshopRegisterScreen({super.key});

  @override
  State<WorkshopRegisterScreen> createState() => _WorkshopRegisterScreenState();
}

class _WorkshopRegisterScreenState extends State<WorkshopRegisterScreen> {
  final _cnpj = TextEditingController();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _password = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _cnpj.dispose();
    _name.dispose();
    _address.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final state = AppScope.read(context);
      // Signup returns a session token, so the new shop lands straight on the
      // dashboard instead of being sent back to log in.
      final session = await state.workshops.createWorkshop(
        cnpj: _cnpj.text,
        name: _name.text,
        password: _password.text,
        address: _address.text,
      );
      if (!mounted) return;
      state.signIn(session);
      Navigator.pushReplacementNamed(context, Routes.dashboard);
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
      appBar: AppBar(title: const Text('Cadastrar Oficina')),
      body: ListView(
        padding: const EdgeInsets.all(MtSizes.screenPadding),
        children: [
          const MtFootnote(
            'Crie a conta da sua oficina para registrar serviços. '
            'O CNPJ é verificado antes do primeiro registro.',
          ),
          const SizedBox(height: 16),
          MtCard(
            child: Column(
              children: [
                MtField(
                  label: 'CNPJ',
                  hint: '00.000.000/0001-00',
                  helper: 'Usado para verificar a oficina',
                  mono: true,
                  controller: _cnpj,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 14),
                MtField(
                  label: 'Nome da oficina',
                  hint: 'Oficina do Zé',
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 14),
                MtField(
                  label: 'Endereço',
                  hint: 'Rua, número — cidade/UF',
                  controller: _address,
                  textCapitalization: TextCapitalization.words,
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
                  key: const Key('cadastro-oficina-salvar'),
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
                      : const Text('Cadastrar Oficina'),
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
