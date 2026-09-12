import 'package:flutter/material.dart';

import '../main.dart';
import '../repositories/service_record_repository.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import '../widgets/feedback.dart';
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

  PlateHistory? _history;
  bool _searched = false;
  bool _busy = false;

  @override
  void dispose() {
    _plate.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_plate.text.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      // No token is sent: this lookup is public by design, and it is the
      // reason the product exists (ARCHITECTURE.md section 3).
      final history = await AppScope.read(
        context,
      ).serviceRecords.historyByPlate(_plate.text);
      if (!mounted) return;
      setState(() {
        _history = history;
        _searched = true;
      });
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
                  onPressed: _busy ? null : _search,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(MtSizes.controlHeight),
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Consultar'),
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
          if (_searched && _history == null)
            MtCard(
              padding: const EdgeInsets.all(28),
              child: const Text(
                'Nenhum veículo encontrado para essa placa.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: MtColors.slate500),
              ),
            ),
          if (_history != null) ..._results(_history!),
        ],
      ),
    );
  }

  List<Widget> _results(PlateHistory history) {
    final vehicle = history.vehicle;
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
              'Placa ${vehicle.plate} · ${history.records.length} '
              '${history.records.length == 1 ? 'serviço' : 'serviços'} registrados',
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
      if (history.records.isEmpty)
        const MtEmptyState(
          message: 'Esta moto ainda não tem serviços registrados.',
          icon: Icons.history_outlined,
        ),
      for (final record in history.records) ...[
        InkWell(
          key: Key('history-${record.id}'),
          onTap: () => Navigator.pushNamed(
            context,
            Routes.serviceDetail,
            arguments: ServiceDetailArgs(record: record),
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
                      record.formattedDate,
                      style: const TextStyle(
                        fontSize: 12,
                        color: MtColors.slate500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    record.workshopName,
                    ?record.mechanicName,
                    '${record.mileageKm} km',
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 12,
                    color: MtColors.slate500,
                  ),
                ),
                if (record.notes != null && record.notes!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    record.notes!,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    ];
  }
}
