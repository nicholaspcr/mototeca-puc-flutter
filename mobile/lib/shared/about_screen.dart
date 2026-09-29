import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/mt_widgets.dart';

/// Sobre o App — static information screen.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _features = [
    'Cadastro do veículo pela placa, no padrão brasileiro',
    'Fotos da nota fiscal e do serviço realizado em cada registro',
    'Histórico completo, mesmo entre oficinas diferentes',
    'Lembretes de manutenção por km ou tempo',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sobre o App')),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: MtSizes.screenPadding,
          vertical: 32,
        ),
        children: [
          const Center(child: MtLogo(size: 56)),
          const SizedBox(height: 20),
          const Center(
            child: Text(
              'Mototeca',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.55,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Center(
            child: Text(
              'Versão 0.1 · Sprint 2',
              style: TextStyle(fontSize: 13, color: MtColors.slate500),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'A Mototeca guarda o histórico de manutenção de motos num só lugar. '
            'Oficinas registram cada serviço feito; proprietários consultam o histórico '
            'completo da moto — de qualquer oficina — pela placa, a qualquer momento.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.6),
          ),
          const SizedBox(height: 20),
          MtCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Principais funcionalidades',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                for (final feature in _features) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: MtColors.petrol,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          feature,
                          style: const TextStyle(fontSize: 13, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          const MtFootnote(
            'Desenvolvido para a disciplina de Desenvolvimento Móvel — PUC',
            align: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
