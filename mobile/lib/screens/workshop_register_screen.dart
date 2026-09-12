import 'package:flutter/material.dart';

import '../main.dart';
import '../theme.dart';
import '../widgets/mt_widgets.dart';

/// Cadastrar Oficina — CNPJ-verified onboarding (ARCHITECTURE.md §6).
class WorkshopRegisterScreen extends StatelessWidget {
  const WorkshopRegisterScreen({super.key});

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
                const MtField(
                  label: 'CNPJ',
                  hint: '00.000.000/0001-00',
                  helper: 'Usado para verificar a oficina',
                  mono: true,
                ),
                const SizedBox(height: 14),
                const MtField(label: 'Nome da oficina', hint: 'Oficina do Zé'),
                const SizedBox(height: 14),
                const MtField(
                  label: 'Endereço',
                  hint: 'Rua, número — cidade/UF',
                ),
                const SizedBox(height: 14),
                const MtField(
                  label: 'Celular (WhatsApp)',
                  hint: '(31) 90000-0000',
                ),
                const SizedBox(height: 14),
                const MtField(
                  label: 'Senha',
                  hint: 'Mínimo de 8 caracteres',
                  obscure: true,
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  key: const Key('cadastro-oficina-salvar'),
                  onPressed: () =>
                      Navigator.pushReplacementNamed(context, Routes.dashboard),
                  child: const Text('Cadastrar Oficina'),
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
