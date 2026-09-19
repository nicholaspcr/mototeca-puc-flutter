import 'package:flutter/material.dart';

import '../demo/demo_backend.dart';
import '../demo/demo_client.dart';
import '../main.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import '../widgets/feedback.dart';
import '../widgets/mt_widgets.dart';

enum LoginRole { oficina, proprietario }

/// Tela inicial — entry point for both personas (design/Main.dc.html).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _cnpj = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();

  LoginRole _role = LoginRole.oficina;
  bool _busy = false;

  bool get _isOficina => _role == LoginRole.oficina;

  @override
  void dispose() {
    _cnpj.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final state = AppScope.read(context);

      if (_isOficina) {
        final session = await state.workshops.login(
          cnpj: _cnpj.text,
          password: _password.text,
        );
        if (!mounted) return;
        state.signIn(session);
        Navigator.pushReplacementNamed(context, Routes.dashboard);
      } else {
        final session = await state.owners.login(
          phone: _phone.text,
          password: _password.text,
        );
        if (!mounted) return;
        state.signInAsOwner(session);
        Navigator.pushReplacementNamed(context, Routes.myVehicles);
      }
    } catch (error) {
      if (!mounted) return;
      showApiError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                if (demoMode) ...[
                  const SizedBox(height: 4),
                  const MtFootnote(
                    'Modo demonstração: dados de exemplo no próprio aparelho, '
                    'sem servidor. Oficina $demoCNPJ · proprietário $demoPhone '
                    '· senha $demoPassword.',
                    align: TextAlign.center,
                  ),
                ],
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
          ] else ...[
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
          ],
          const SizedBox(height: 18),
          ElevatedButton(
            key: const Key('login-entrar'),
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
          Center(
            child: TextButton(
              key: const Key('login-cadastrar-oficina'),
              onPressed: () => Navigator.pushNamed(
                context,
                _isOficina ? Routes.workshopRegister : Routes.ownerRegister,
              ),
              child: Text(
                _isOficina
                    ? 'Não tem conta? Cadastre sua oficina'
                    : 'Não tem conta? Cadastre-se',
                style: const TextStyle(color: MtColors.rust),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
