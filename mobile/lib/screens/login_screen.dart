import 'package:flutter/material.dart';

import '../main.dart';
import '../theme.dart';
import '../widgets/mt_widgets.dart';

enum LoginRole { oficina, proprietario }

/// Tela inicial — entry point for both personas (design/Main.dc.html).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  LoginRole _role = LoginRole.oficina;

  bool get _isOficina => _role == LoginRole.oficina;

  void _submit() {
    Navigator.pushReplacementNamed(
      context,
      _isOficina ? Routes.dashboard : Routes.myVehicles,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: MtSizes.screenPadding,
              vertical: 32,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    MtLogo(size: 30),
                    SizedBox(width: 9),
                    Text(
                      'Mototeca',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.65,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Histórico de manutenção de motos',
                  style: TextStyle(fontSize: 14, color: MtColors.slate500),
                ),
                const SizedBox(height: 24),
                _roleSelector(),
                const SizedBox(height: 24),
                _loginCard(),
                const SizedBox(height: 24),
                const MtFootnote(
                  'Consultar o histórico de uma moto não exige cadastro — '
                  'use o Portal do Proprietário.',
                  align: TextAlign.center,
                ),
                const SizedBox(height: 12),
                TextButton(
                  key: const Key('login-consulta'),
                  onPressed: () =>
                      Navigator.pushNamed(context, Routes.customerPortal),
                  child: const Text(
                    'Consultar sem cadastro',
                    style: TextStyle(
                      color: MtColors.rust,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('login-sobre'),
                  onPressed: () => Navigator.pushNamed(context, Routes.about),
                  child: const Text(
                    'Sobre o app',
                    style: TextStyle(color: MtColors.slate500),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _roleSelector() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(MtSizes.controlRadius),
        border: Border.all(color: MtColors.slate200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          _roleTab(
            'Sou da oficina',
            LoginRole.oficina,
            const Key('role-oficina'),
          ),
          _roleTab(
            'Sou proprietário',
            LoginRole.proprietario,
            const Key('role-proprietario'),
          ),
        ],
      ),
    );
  }

  Widget _roleTab(String label, LoginRole role, Key key) {
    final active = _role == role;
    return Expanded(
      child: InkWell(
        key: key,
        onTap: () => setState(() => _role = role),
        child: Container(
          height: MtSizes.controlHeight,
          alignment: Alignment.center,
          color: active ? MtColors.petrol : Colors.white,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: active ? MtColors.slate50 : MtColors.graphite,
            ),
          ),
        ),
      ),
    );
  }

  Widget _loginCard() {
    return MtCard(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Entrar',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.55,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _isOficina
                ? 'Acesse o painel da sua oficina'
                : 'Acesse o histórico das suas motos',
            style: const TextStyle(fontSize: 14, color: MtColors.slate500),
          ),
          const SizedBox(height: 16),
          if (_isOficina) ...[
            const MtField(
              label: 'CNPJ da oficina',
              hint: '00.000.000/0001-00',
              mono: true,
            ),
            const SizedBox(height: 14),
            const MtField(label: 'Senha', hint: 'Sua senha', obscure: true),
          ] else ...[
            const MtField(label: 'Celular', hint: '(31) 90000-0000'),
            const SizedBox(height: 14),
            const MtField(
              label: 'Código recebido por WhatsApp',
              hint: '000000',
              mono: true,
            ),
          ],
          const SizedBox(height: 18),
          ElevatedButton(
            key: const Key('login-entrar'),
            onPressed: _submit,
            child: const Text('Entrar'),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              key: const Key('login-cadastrar-oficina'),
              onPressed: () =>
                  Navigator.pushNamed(context, Routes.workshopRegister),
              child: const Text(
                'Não tem conta? Cadastre sua oficina',
                style: TextStyle(color: MtColors.rust),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
