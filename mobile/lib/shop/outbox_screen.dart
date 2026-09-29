import 'package:flutter/material.dart';

import '../app/routes.dart';
import '../state/app_scope.dart';
import '../storage/outbox_store.dart';
import '../theme.dart';
import '../widgets/feedback.dart';
import '../widgets/mt_widgets.dart';

/// Fila de Envio — records held on the device (design/Outbox.dc.html).
class OutboxScreen extends StatefulWidget {
  const OutboxScreen({super.key});

  @override
  State<OutboxScreen> createState() => _OutboxScreenState();
}

class _OutboxScreenState extends State<OutboxScreen> {
  bool _sending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppScope.read(context).outbox.load();
  }

  Future<void> _send() async {
    final state = AppScope.read(context);
    setState(() => _sending = true);
    try {
      final result = await state.outbox.flush(state.serviceRecords);
      if (!mounted) return;
      if (result.failed > 0) {
        showApiError(
          context,
          '${result.failed} registro(s) não subiram e continuam na fila.',
        );
      } else if (result.sent > 0) {
        showSuccess(context, '${result.sent} registro(s) publicados.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final signedIn = state.workshop != null;

    return Scaffold(
      appBar: const MtAppBar(title: 'Fila de Envio'),
      body: ListenableBuilder(
        listenable: state.outbox,
        builder: (context, _) {
          final drafts = state.outbox.drafts;
          return ListView(
            padding: const EdgeInsets.all(MtSizes.screenPadding),
            children: [
              if (!signedIn) ...[_signInCard(), const SizedBox(height: 16)],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Neste aparelho',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${drafts.length} '
                    '${drafts.length == 1 ? 'registro' : 'registros'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: MtColors.slate500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (drafts.isEmpty)
                const MtEmptyState(
                  message:
                      'Nada aguardando envio.\n'
                      'Um registro novo fica aqui até ser publicado.',
                  icon: Icons.outbox_outlined,
                )
              else
                for (final draft in drafts) ...[
                  _draftTile(draft, signedIn),
                  const SizedBox(height: 12),
                ],
              if (signedIn && drafts.isNotEmpty) ...[
                const SizedBox(height: 4),
                ElevatedButton(
                  key: const Key('fila-enviar'),
                  onPressed: _sending ? null : _send,
                  child: Text(
                    _sending ? 'Enviando…' : 'Enviar tudo agora',
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const MtFootnote(
                'Um registro enviado não pode ser apagado — só corrigido por '
                'outro registro que o substitui.',
                align: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _draftTile(OutboxDraft draft, bool signedIn) {
    return MtCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      draft.plate,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      draft.vehicleLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              signedIn
                  ? const MtBadge(
                      label: 'Na fila',
                      background: Color(0x29EAB308),
                      foreground: MtColors.warningText,
                    )
                  : const MtBadge(
                      label: 'Aguardando conta',
                      background: MtColors.slate100,
                      foreground: MtColors.slate500,
                    ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            draft.operationsLabel,
            style: const TextStyle(
              fontSize: 12,
              color: MtColors.slate500,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${draft.mileageKm} km · ${_savedAt(draft.savedAt)}'
            '${draft.attachmentCount == 0 ? '' : ' · ${draft.attachmentCount} '
                  '${draft.attachmentCount == 1 ? 'foto' : 'fotos'}'}',
            style: const TextStyle(fontSize: 12, color: MtColors.slate500),
          ),
        ],
      ),
    );
  }

  String _savedAt(DateTime moment) {
    final now = DateTime.now();
    final sameDay =
        moment.year == now.year &&
        moment.month == now.month &&
        moment.day == now.day;
    final clock =
        '${moment.hour.toString().padLeft(2, '0')}:'
        '${moment.minute.toString().padLeft(2, '0')}';
    if (sameDay) return 'salvo hoje, $clock';
    final date =
        '${moment.day.toString().padLeft(2, '0')}/'
        '${moment.month.toString().padLeft(2, '0')}';
    return 'salvo $date, $clock';
  }

  Widget _signInCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MtColors.petrolTint,
        border: Border.all(color: MtColors.petrolBorder),
        borderRadius: BorderRadius.circular(MtSizes.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Nada é enviado antes de você entrar',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: MtColors.petrol,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Os registros ficam salvos aqui pelo tempo que for preciso. Entre '
            'com o CNPJ para publicá-los no histórico das motos.',
            style: TextStyle(
              fontSize: 13,
              color: MtColors.petrol,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            key: const Key('fila-entrar'),
            onPressed: () => Navigator.pushNamed(context, Routes.signIn),
            child: const Text('Entrar e enviar'),
          ),
        ],
      ),
    );
  }
}
