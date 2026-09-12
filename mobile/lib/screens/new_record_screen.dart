import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../theme.dart';
import '../widgets/mt_widgets.dart';

/// Novo Registro — the app's main action (design/NewRecord.dc.html).
class NewRecordScreen extends StatefulWidget {
  const NewRecordScreen({super.key});

  @override
  State<NewRecordScreen> createState() => _NewRecordScreenState();
}

class _NewRecordScreenState extends State<NewRecordScreen> {
  final _plate = TextEditingController(text: 'ABC1D23');
  final _selectedOps = <String>{};
  Vehicle? _vehicle;
  bool _searched = false;

  @override
  void dispose() {
    _plate.dispose();
    super.dispose();
  }

  void _search() {
    setState(() {
      _vehicle = findVehicleByPlate(_plate.text);
      _searched = true;
    });
  }

  void _save() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Registro salvo com sucesso.')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Novo Registro')),
      body: ListView(
        padding: const EdgeInsets.all(MtSizes.screenPadding),
        children: [
          _vehicleCard(),
          if (_searched) ...[
            const SizedBox(height: 16),
            _operationsCard(),
            const SizedBox(height: 16),
            _detailsCard(),
            const SizedBox(height: 16),
            ElevatedButton(
              key: const Key('novo-registro-salvar'),
              onPressed: _save,
              child: const Text('Salvar Registro'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _vehicleCard() {
    return MtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Veículo',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _plate,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
                  decoration: const InputDecoration(hintText: 'ABC1D23'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: OutlinedButton(
                  key: const Key('novo-registro-buscar'),
                  onPressed: _search,
                  child: const Text('Buscar'),
                ),
              ),
            ],
          ),
          if (_searched && _vehicle == null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: MtColors.warning.withValues(alpha: 0.12),
                border: Border.all(
                  color: MtColors.warning.withValues(alpha: 0.4),
                ),
                borderRadius: BorderRadius.circular(MtSizes.controlRadius),
              ),
              child: Text(
                'Veículo não encontrado. Um novo cadastro será criado ao salvar '
                'este registro para a placa ${_plate.text.toUpperCase()}.',
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            ),
          ],
          if (_vehicle != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: MtColors.slate100,
                borderRadius: BorderRadius.circular(MtSizes.controlRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_vehicle!.labelWithYear} · ${_vehicle!.plate}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Proprietário: ${_vehicle!.owner}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: MtColors.slate500,
                    ),
                  ),
                  Text(
                    'Última km registrada: ${_vehicle!.mileageKm} km',
                    style: const TextStyle(
                      fontSize: 12,
                      color: MtColors.slate500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _operationsCard() {
    return MtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Operação Realizada',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final op in operationTaxonomy)
                MtChip(
                  label: op,
                  selected: _selectedOps.contains(op),
                  onTap: () => setState(() {
                    _selectedOps.contains(op)
                        ? _selectedOps.remove(op)
                        : _selectedOps.add(op);
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailsCard() {
    return MtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Detalhes',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: MtField(
                  label: 'Km atual',
                  hint: '18500',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: MtField(
                  label: 'Valor (R\$)',
                  hint: '245,00',
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const MtField(label: 'Peças utilizadas', hint: 'Nome da peça'),
          const SizedBox(height: 16),
          const MtField(
            label: 'Observações',
            hint: 'Detalhes do serviço, recomendações para a próxima visita...',
          ),
          const SizedBox(height: 16),
          const Text(
            'Fotos (antes/depois)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Row(
            children: const [
              Expanded(child: _PhotoSlot(label: 'Foto antes')),
              SizedBox(width: 10),
              Expanded(child: _PhotoSlot(label: 'Foto depois')),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: MtColors.slate50,
        border: Border.all(color: MtColors.slate200),
        borderRadius: BorderRadius.circular(MtSizes.controlRadius),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image_outlined, color: Color(0xFF94A3B8)),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: MtColors.slate500),
          ),
        ],
      ),
    );
  }
}
