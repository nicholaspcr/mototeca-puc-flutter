import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/mt_widgets.dart';
import 'service_detail_screen.dart';

/// Portal do Proprietário — public plate lookup, no account required.
class CustomerPortalScreen extends StatefulWidget {
  const CustomerPortalScreen({super.key});

  @override
  State<CustomerPortalScreen> createState() => _CustomerPortalScreenState();
}

class _CustomerPortalScreenState extends State<CustomerPortalScreen> {
  final _plate = TextEditingController();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 84,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: const [
                MtLogo(size: 24),
                SizedBox(width: 9),
                Text(
                  'Mototeca',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Consulte o histórico de qualquer moto pela placa',
              style: TextStyle(
                fontSize: 13,
                color: MtColors.slate500,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(MtSizes.screenPadding),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _plate,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
                  decoration: const InputDecoration(hintText: 'EX: ABC1D23'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 116,
                child: ElevatedButton(
                  key: const Key('portal-consultar'),
                  onPressed: _search,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(MtSizes.controlHeight),
                  ),
                  child: const Text('Consultar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (!_searched)
            const MtFootnote(
              'Não é necessário criar conta para consultar o histórico. '
              'Um cadastro só é pedido para reivindicar a propriedade da moto.',
              align: TextAlign.center,
            ),
          if (_searched && _vehicle == null)
            MtCard(
              padding: const EdgeInsets.all(28),
              child: const Text(
                'Nenhum veículo encontrado para essa placa.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: MtColors.slate500),
              ),
            ),
          if (_vehicle != null) ..._results(_vehicle!),
        ],
      ),
    );
  }

  List<Widget> _results(Vehicle vehicle) {
    return [
      MtCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              vehicle.labelWithYear,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Placa ${vehicle.plate} · ${vehicle.color} · ${vehicle.mileageKm} km atuais',
              style: const TextStyle(fontSize: 13, color: MtColors.slate500),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Resumo em PDF gerado.')),
              ),
              child: const Text('Baixar PDF'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'Histórico de Serviços',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      for (final record in vehicle.history) ...[
        InkWell(
          key: Key('history-${record.id}'),
          onTap: () => Navigator.pushNamed(
            context,
            Routes.serviceDetail,
            arguments: ServiceDetailArgs(vehicle: vehicle, record: record),
          ),
          borderRadius: BorderRadius.circular(MtSizes.cardRadius),
          child: MtCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        record.operationsLabel,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      record.date,
                      style: const TextStyle(
                        fontSize: 12,
                        color: MtColors.slate500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${record.workshop} · ${record.mechanic} · ${record.mileageKm} km',
                  style: const TextStyle(
                    fontSize: 12,
                    color: MtColors.slate500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  record.notes,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    ];
  }
}
