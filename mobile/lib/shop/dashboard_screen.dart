import 'package:flutter/material.dart';

import '../main.dart';
import '../models/service_record.dart';
import '../repositories/service_record_repository.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import '../widgets/feedback.dart';
import '../widgets/mt_widgets.dart';
import 'service_detail_screen.dart';

/// Painel da Oficina — the mechanic's home (design/Dashboard.dc.html).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _plate = TextEditingController();

  Future<WorkshopFeed>? _feed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Kicked off here rather than initState because it needs AppScope.
    _feed ??= AppScope.read(context).serviceRecords.workshopFeed();
  }

  @override
  void dispose() {
    _plate.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final reloaded = AppScope.read(context).serviceRecords.workshopFeed();
    // Block body: an arrow would hand setState a Future-returning closure.
    setState(() {
      _feed = reloaded;
    });
    // The FutureBuilder renders the failure; awaiting it here too would make
    // the same error unhandled a second time.
    try {
      await reloaded;
    } on Object {
      // handled above
    }
  }

  void _signOut() {
    AppScope.read(context).signOut();
    Navigator.pushReplacementNamed(context, Routes.login);
  }

  Future<void> _openNewRecord({String? plate}) async {
    final created = await Navigator.pushNamed(
      context,
      Routes.newRecord,
      arguments: plate,
    );
    if (created == true && mounted) await _reload();
  }

  /// The search box promises history, so it opens the history view — the same
  /// public lookup the owner portal uses.
  void _openHistory() {
    if (_plate.text.trim().isEmpty) return;
    Navigator.pushNamed(context, Routes.customerPortal, arguments: _plate.text);
  }

  @override
  Widget build(BuildContext context) {
    final workshop = AppScope.of(context).workshop;

    return Scaffold(
      appBar: MtHomeHeader(
        subtitle: 'Bem-vindo, ${workshop?.name ?? 'oficina'}',
        onSignOut: _signOut,
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<WorkshopFeed>(
          future: _feed,
          builder: (context, snapshot) {
            final feed = snapshot.data;
            return ListView(
              padding: const EdgeInsets.all(MtSizes.screenPadding),
              children: [
                _monthBanner(snapshot, feed),
                const SizedBox(height: 20),
                _searchCard(),
                const SizedBox(height: 20),
                _newRecordCard(),
                const SizedBox(height: 20),
                const Text(
                  'Registros Recentes',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                ..._recentSection(snapshot, feed),
                const SizedBox(height: 4),
                OutlinedButton(
                  key: const Key('dashboard-cadastrar-veiculo'),
                  onPressed: () =>
                      Navigator.pushNamed(context, Routes.vehicleRegister),
                  child: const Text('Cadastrar veículo'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _recentSection(
    AsyncSnapshot<WorkshopFeed> snapshot,
    WorkshopFeed? feed,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const [MtLoading()];
    }
    if (snapshot.hasError) {
      return [
        MtEmptyState(
          message: snapshot.error is Object
              ? 'Não foi possível carregar os registros.'
              : '',
          icon: Icons.cloud_off_outlined,
          onRetry: _reload,
        ),
      ];
    }
    final records = feed?.records ?? const <ServiceRecord>[];
    if (records.isEmpty) {
      return const [
        MtEmptyState(
          message:
              'Nenhum serviço registrado ainda.\n'
              'Use "Criar Registro" para lançar o primeiro.',
          icon: Icons.build_outlined,
        ),
      ];
    }
    return [
      for (final record in records) ...[
        _recordTile(record),
        const SizedBox(height: 8),
      ],
    ];
  }

  Widget _monthBanner(
    AsyncSnapshot<WorkshopFeed> snapshot,
    WorkshopFeed? feed,
  ) {
    final count = feed?.countThisMonth;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: MtColors.petrolTint,
        border: Border.all(color: MtColors.petrolBorder),
        borderRadius: BorderRadius.circular(MtSizes.cardRadius),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          const Flexible(
            child: Text(
              'Serviços registrados este mês',
              style: TextStyle(
                fontSize: 13,
                color: MtColors.petrol,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            count?.toString() ?? '—',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: MtColors.petrol,
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchCard() {
    return MtCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Buscar Veículo',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text(
            'Consulte o histórico pela placa',
            style: TextStyle(fontSize: 13, color: MtColors.slate500),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _plate,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
                  decoration: const InputDecoration(hintText: 'ABC1D23'),
                  onSubmitted: (_) => _openHistory(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: OutlinedButton(
                  key: const Key('dashboard-buscar'),
                  onPressed: _openHistory,
                  child: const Text('Buscar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _newRecordCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MtColors.petrol,
        borderRadius: BorderRadius.circular(MtSizes.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Novo Registro',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: MtColors.slate50,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Lançar um serviço realizado agora',
            style: TextStyle(fontSize: 13, color: MtColors.petrolBorder),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            key: const Key('dashboard-criar-registro'),
            onPressed: _openNewRecord,
            style: ElevatedButton.styleFrom(
              backgroundColor: MtColors.slate50,
              foregroundColor: MtColors.petrol,
              minimumSize: const Size.fromHeight(MtSizes.controlHeight),
            ),
            child: const Text('Criar Registro'),
          ),
        ],
      ),
    );
  }

  Widget _recordTile(ServiceRecord record) {
    return InkWell(
      key: Key('record-${record.id}'),
      onTap: () async {
        final corrected = await Navigator.pushNamed(
          context,
          Routes.serviceDetail,
          arguments: ServiceDetailArgs(record: record, canRevise: true),
        );
        if (corrected == true && mounted) await _reload();
      },
      borderRadius: BorderRadius.circular(MtSizes.cardRadius),
      child: MtCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        record.vehicle.plate,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        record.vehicle.label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    record.operationsLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      color: MtColors.slate500,
                    ),
                  ),
                  Text(
                    '${record.formattedDate} · ${record.mileageKm} km',
                    style: const TextStyle(
                      fontSize: 12,
                      color: MtColors.slate500,
                    ),
                  ),
                ],
              ),
            ),
            if (record.mechanicName != null) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: MtColors.slate100,
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Text(
                  record.mechanicName!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: MtColors.rust,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
