import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/mt_widgets.dart';

/// Cadastrar Veículo — fields mirror CreateVehicleRequest in proto/.
class VehicleRegisterScreen extends StatelessWidget {
  const VehicleRegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cadastrar Veículo')),
      body: ListView(
        padding: const EdgeInsets.all(MtSizes.screenPadding),
        children: [
          const MtFootnote(
            'Cadastre a moto pela placa — o histórico de manutenção fica vinculado '
            'a ela e acompanha o veículo mesmo se for atendido em outra oficina.',
          ),
          const SizedBox(height: 16),
          MtCard(
            child: Column(
              children: [
                const MtField(
                  label: 'Placa',
                  hint: 'ABC1D23',
                  helper: 'Formato antigo ou Mercosul, sem hífen',
                  mono: true,
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 14),
                const MtField(
                  label: 'Chassi',
                  hint: '9BWZZZ377VT004251',
                  helper: '17 caracteres',
                  mono: true,
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Expanded(
                      child: MtField(label: 'Marca', hint: 'Honda'),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: MtField(label: 'Modelo', hint: 'CG 160'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const MtField(
                  label: 'Ano',
                  hint: '2022',
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  key: const Key('cadastro-veiculo-salvar'),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Veículo cadastrado.')),
                    );
                    Navigator.pop(context);
                  },
                  child: const Text('Cadastrar Veículo'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
