import 'package:flutter/material.dart';

import '../state/app_scope.dart';
import '../theme.dart';
import '../widgets/feedback.dart';
import '../widgets/mt_widgets.dart';

/// Cadastrar Veículo — fields mirror CreateVehicleRequest in proto/.
class VehicleRegisterScreen extends StatefulWidget {
  const VehicleRegisterScreen({super.key, this.initialPlate});

  /// Pre-filled when the mechanic got here from a failed plate search.
  final String? initialPlate;

  @override
  State<VehicleRegisterScreen> createState() => _VehicleRegisterScreenState();
}

class _VehicleRegisterScreenState extends State<VehicleRegisterScreen> {
  late final _plate = TextEditingController(text: widget.initialPlate ?? '');
  final _chassi = TextEditingController();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _year = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _plate.dispose();
    _chassi.dispose();
    _make.dispose();
    _model.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final int year;
    try {
      year = int.parse(_year.text.trim());
    } on FormatException {
      showApiError(context, 'Informe o ano com 4 dígitos.');
      return;
    }

    setState(() => _saving = true);
    try {
      // Field-level rules (plate format, 17-char chassi, year range) live in
      // the backend so the two sides cannot disagree; the message it returns
      // is what the user sees.
      await AppScope.read(context).vehicles.create(
        plate: _plate.text,
        chassi: _chassi.text,
        make: _make.text,
        model: _model.text,
        year: year,
      );
      if (!mounted) return;
      showSuccess(context, 'Veículo cadastrado.');
      Navigator.pop(context, true);
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
                MtField(
                  label: 'Placa',
                  hint: 'ABC1D23',
                  helper: 'Formato antigo ou Mercosul, sem hífen',
                  mono: true,
                  controller: _plate,
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 14),
                MtField(
                  label: 'Chassi',
                  hint: '9BWZZZ377VT004251',
                  helper: '17 caracteres',
                  mono: true,
                  controller: _chassi,
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: MtField(
                        label: 'Marca',
                        hint: 'Honda',
                        controller: _make,
                        textCapitalization: TextCapitalization.words,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MtField(
                        label: 'Modelo',
                        hint: 'CG 160',
                        controller: _model,
                        textCapitalization: TextCapitalization.words,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                MtField(
                  label: 'Ano',
                  hint: '2022',
                  controller: _year,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  key: const Key('cadastro-veiculo-salvar'),
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
                      : const Text('Cadastrar Veículo'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
