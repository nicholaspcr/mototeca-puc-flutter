import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../app/routes.dart';
import '../models/owner.dart';
import '../models/vehicle.dart';
import '../shared/service_detail_screen.dart';
import '../state/app_scope.dart';
import '../storage/garage_store.dart';
import '../theme.dart';
import '../widgets/feedback.dart';
import '../widgets/mt_widgets.dart';

/// Minha Garagem (design/MyVehicles.dc.html). Signed out it lists the bikes
/// held on the device; signed in, the ones the server owns.
class GarageScreen extends StatefulWidget {
  const GarageScreen({super.key});

  @override
  State<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends State<GarageScreen> {
  Future<List<OwnedVehicle>>? _vehicles;

  bool get _signedIn => AppScope.read(context).owner != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppScope.read(context).garage.ensureLoaded();
    if (_signedIn) _vehicles ??= AppScope.read(context).owners.myVehicles();
  }

  Future<void> _reload() async {
    if (!_signedIn) return;
    final reloaded = AppScope.read(context).owners.myVehicles();
    setState(() {
      _vehicles = reloaded;
    });
    // The FutureBuilder shows the error; here we only wait for the reload.
    try {
      await reloaded;
    } on Object {
      return;
    }
  }

  /// Unlinks the bike after the owner confirms. Nothing in its history
  /// changes; the buyer claims it with the chassi, as anyone would.
  Future<void> _release(OwnedVehicle vehicle) async {
    final confirmed = await _confirmRelease(vehicle.label, vehicle.plate);
    if (!confirmed || !mounted) return;

    try {
      await AppScope.read(context).owners.releaseVehicle(vehicle.plate);
      if (!mounted) return;
      showSuccess(context, 'Moto desvinculada.');
      await _reload();
    } catch (error) {
      if (!mounted) return;
      showApiError(context, error);
    }
  }

  Future<void> _removeLocal(LocalBike bike) async {
    final confirmed = await _confirm(
      title: 'Remover moto',
      message:
          '${bike.label} (${bike.plate}) e as anotações dela saem deste '
          'aparelho.',
      action: 'Remover',
    );
    if (!confirmed || !mounted) return;
    try {
      await AppScope.read(context).garage.remove(bike.id!);
      if (mounted) showSuccess(context, 'Moto removida deste aparelho.');
    } on Object {
      if (mounted) showApiError(context, localSaveFailed);
    }
  }

  Future<bool> _confirmRelease(String label, String plate) => _confirm(
    title: 'Desvincular moto',
    message:
        '$label ($plate) sai da sua lista. O histórico continua com a '
        'placa, e o novo dono pode vinculá-la.',
    action: 'Desvincular',
  );

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const Key('vehicle-release-confirmar'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _addVehicle() async {
    if (!_signedIn) return _editLocalBike();

    final claim = await showDialog<_Claim>(
      context: context,
      builder: (_) => const _ClaimDialog(),
    );
    if (claim == null || !mounted) return;

    try {
      final linked = await _claimOrRegister(claim);
      if (!linked || !mounted) return;
      showSuccess(context, 'Moto vinculada.');
      await _reload();
    } catch (error) {
      if (!mounted) return;
      showApiError(context, error);
    }
  }

  Future<void> _editLocalBike([LocalBike? initial]) async {
    final bike = await showDialog<LocalBike>(
      context: context,
      builder: (_) => _LocalBikeDialog(initial: initial),
    );
    if (bike == null || !mounted) return;
    try {
      await AppScope.read(context).garage.save(bike);
      if (!mounted) return;
      showSuccess(
        context,
        initial == null ? 'Moto salva neste aparelho.' : 'Moto atualizada.',
      );
    } on DuplicatePlateException catch (error) {
      if (mounted) showApiError(context, error.toString());
    } on Object {
      if (mounted) showApiError(context, localSaveFailed);
    }
  }

  /// Claims by plate first, so a bike a shop already registered brings its
  /// history along. Only an unknown plate needs the registration form.
  Future<bool> _claimOrRegister(_Claim claim) async {
    final owners = AppScope.read(context).owners;
    try {
      await owners.claimVehicle(claim.plate, claim.chassiSuffix);
      return true;
    } on ApiException catch (error) {
      if (error.code != ApiErrorCode.notFound) rethrow;
    }
    if (!mounted) return false;

    final created = await Navigator.pushNamed(
      context,
      Routes.vehicleRegister,
      arguments: normalizePlate(claim.plate),
    );
    if (created is! Vehicle) return false;
    // The owner just typed the whole chassi, so its end is known.
    await owners.claimVehicle(created.plate, created.chassiSuffix);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final signedIn = state.owner != null;

    return Scaffold(
      appBar: MtAppBar(
        title: 'Minha Garagem',
        status: signedIn
            ? 'Sincronizada com a conta de ${state.owner?.name ?? ''}'
            : 'Sem conta · salva neste aparelho',
      ),
      body: signedIn
          ? RefreshIndicator(
              onRefresh: _reload,
              child: FutureBuilder<List<OwnedVehicle>>(
                future: _vehicles,
                builder: _remoteBody,
              ),
            )
          : ListenableBuilder(
              listenable: state.garage,
              builder: (context, _) => _localBody(state.garage),
            ),
    );
  }

  Widget _localBody(LocalGarage garage) {
    return ListView(
      padding: const EdgeInsets.all(MtSizes.screenPadding),
      children: [
        _sectionHeader(garage.length),
        const SizedBox(height: 16),
        if (garage.isEmpty)
          const MtEmptyState(
            message:
                'Nenhuma moto neste aparelho.\n'
                'Adicione a primeira pela placa.',
            icon: Icons.two_wheeler_outlined,
          ),
        for (final bike in garage.bikes) ...[
          _localTile(bike),
          const SizedBox(height: 16),
        ],
        _addButton(),
        const SizedBox(height: 16),
        _syncCard(),
        const SizedBox(height: 16),
        _remindersCard(0),
      ],
    );
  }

  Widget _remoteBody(
    BuildContext context,
    AsyncSnapshot<List<OwnedVehicle>> snapshot,
  ) {
    final vehicles = snapshot.data ?? const <OwnedVehicle>[];
    final dueCount = vehicles.where((v) => v.reminderIsDue).length;

    return ListView(
      padding: const EdgeInsets.all(MtSizes.screenPadding),
      children: [
        _sectionHeader(snapshot.hasData ? vehicles.length : null),
        const SizedBox(height: 16),
        if (snapshot.connectionState == ConnectionState.waiting)
          const MtLoading()
        else if (snapshot.hasError)
          MtEmptyState(
            message: 'Não foi possível carregar suas motos.',
            icon: Icons.cloud_off_outlined,
            onRetry: _reload,
          )
        else if (vehicles.isEmpty)
          const MtEmptyState(
            message:
                'Você ainda não tem motos vinculadas.\n'
                'Cadastre a primeira pela placa.',
            icon: Icons.two_wheeler_outlined,
          ),
        for (final vehicle in vehicles) ...[
          _vehicleTile(context, vehicle),
          const SizedBox(height: 16),
        ],
        _addButton(),
        const SizedBox(height: 16),
        _remindersCard(dueCount),
      ],
    );
  }

  Widget _sectionHeader(int? count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Flexible(
          child: Text(
            'Motos cadastradas',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          count == null ? '' : '$count ${count == 1 ? 'veículo' : 'veículos'}',
          style: const TextStyle(fontSize: 12, color: MtColors.slate500),
        ),
      ],
    );
  }

  Widget _addButton() => ElevatedButton(
    key: const Key('garagem-adicionar'),
    onPressed: _addVehicle,
    child: const Text('+ Adicionar moto'),
  );

  Widget _syncCard() {
    return MtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Entrar para sincronizar',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const MtFootnote(
            'Esta garagem existe só neste aparelho. Com uma conta ela é '
            'guardada no servidor e passa a mostrar os serviços que as '
            'oficinas registraram.',
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('garagem-entrar'),
            onPressed: () => Navigator.pushNamed(context, Routes.signIn),
            child: const Text('Entrar'),
          ),
        ],
      ),
    );
  }

  Widget _remindersCard(int dueCount) {
    return InkWell(
      key: const Key('garagem-lembretes'),
      onTap: () => Navigator.pushNamed(context, Routes.reminders),
      borderRadius: BorderRadius.circular(MtSizes.cardRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: MtColors.petrolTint,
          border: Border.all(color: MtColors.petrolBorder),
          borderRadius: BorderRadius.circular(MtSizes.cardRadius),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Lembretes de manutenção',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: MtColors.petrol,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dueCount == 1
                        ? '1 manutenção próxima'
                        : '$dueCount manutenções próximas',
                    style: const TextStyle(
                      fontSize: 12,
                      color: MtColors.petrol,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: MtColors.petrol, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _localTile(LocalBike bike) {
    return _tile(
      plate: bike.plate,
      label: bike.label,
      detail: [?bike.year, '${bike.mileageKm} km'].join(' · '),
      storage: const MtBadge(
        label: 'Só neste aparelho',
        background: MtColors.slate100,
        foreground: MtColors.slate500,
      ),
      onTap: () => Navigator.pushNamed(
        context,
        Routes.maintenanceNotes,
        arguments: bike,
      ),
      actions: [
        PopupMenuItem(
          key: const Key('vehicle-edit'),
          onTap: () => _editLocalBike(bike),
          child: const Text('Editar'),
        ),
        PopupMenuItem(
          key: const Key('vehicle-release'),
          onTap: () => _removeLocal(bike),
          child: const Text('Remover'),
        ),
      ],
    );
  }

  Widget _vehicleTile(BuildContext context, OwnedVehicle vehicle) {
    final due = vehicle.reminderIsDue;

    return _tile(
      plate: vehicle.plate,
      label: vehicle.label,
      detail:
          '${vehicle.year} · ${vehicle.currentMileageKm} km · '
          '${vehicle.serviceCount} '
          '${vehicle.serviceCount == 1 ? 'serviço' : 'serviços'}',
      storage: const MtBadge(
        label: 'Sincronizada',
        background: Color(0x1F1B4965),
        foreground: MtColors.petrol,
      ),
      reminder: vehicle.reminder.isEmpty
          ? null
          : MtBadge(
              label: vehicle.reminder,
              background: (due ? MtColors.warning : MtColors.success)
                  .withValues(alpha: 0.14),
              foreground: due ? MtColors.warningText : MtColors.successText,
            ),
      // A bike with no service yet has no detail screen to open.
      onTap: vehicle.lastService == null
          ? null
          : () => Navigator.pushNamed(
              context,
              Routes.serviceDetail,
              arguments: ServiceDetailArgs(record: vehicle.lastService!),
            ),
      actions: [
        PopupMenuItem(
          key: const Key('vehicle-release'),
          onTap: () => _release(vehicle),
          child: const Text('Vendi esta moto'),
        ),
      ],
    );
  }

  Widget _tile({
    required String plate,
    required String label,
    required String detail,
    required Widget storage,
    Widget? reminder,
    VoidCallback? onTap,
    required List<PopupMenuEntry<void>> actions,
  }) {
    return InkWell(
      key: Key('vehicle-$plate'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(MtSizes.cardRadius),
      child: MtCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
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
                        plate,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 12,
                      color: MtColors.slate500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [storage, ?reminder],
                  ),
                ],
              ),
            ),
            PopupMenuButton<void>(
              key: Key('vehicle-menu-$plate'),
              tooltip: 'Opções',
              icon: const Icon(
                Icons.more_vert,
                color: MtColors.slate500,
                size: 20,
              ),
              itemBuilder: (_) => actions,
            ),
          ],
        ),
      ),
    );
  }
}

typedef _Claim = ({String plate, String chassiSuffix});

/// Claiming a bike: the plate plus the end of the chassi that proves it.
class _ClaimDialog extends StatefulWidget {
  const _ClaimDialog();

  @override
  State<_ClaimDialog> createState() => _ClaimDialogState();
}

class _ClaimDialogState extends State<_ClaimDialog> {
  final _plate = TextEditingController();
  final _chassiSuffix = TextEditingController();

  @override
  void dispose() {
    _plate.dispose();
    _chassiSuffix.dispose();
    super.dispose();
  }

  void _submit() {
    final plate = _plate.text.trim();
    final suffix = _chassiSuffix.text.trim();
    if (plate.isEmpty) return;
    if (suffix.length != chassiSuffixLength) {
      showApiError(
        context,
        'Informe os $chassiSuffixLength últimos caracteres do chassi.',
      );
      return;
    }
    Navigator.pop<_Claim>(context, (plate: plate, chassiSuffix: suffix));
  }

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      title: 'Adicionar moto',
      onSubmit: _submit,
      children: [
        MtField(
          key: const Key('adicionar-moto-placa'),
          label: 'Placa',
          hint: 'ABC1D23',
          mono: true,
          controller: _plate,
          textCapitalization: TextCapitalization.characters,
        ),
        const SizedBox(height: 14),
        MtField(
          key: const Key('adicionar-moto-chassi'),
          label: 'Final do chassi',
          hint: '000001',
          helper:
              'Os $chassiSuffixLength últimos caracteres, no documento da '
              'moto (CRLV). Provam que ela é sua.',
          mono: true,
          controller: _chassiSuffix,
          textCapitalization: TextCapitalization.characters,
        ),
      ],
    );
  }
}

/// Adding or editing a bike on the device: only what the rider can read off it.
class _LocalBikeDialog extends StatefulWidget {
  const _LocalBikeDialog({this.initial});

  final LocalBike? initial;

  @override
  State<_LocalBikeDialog> createState() => _LocalBikeDialogState();
}

class _LocalBikeDialogState extends State<_LocalBikeDialog> {
  late final _plate = TextEditingController(text: widget.initial?.plate);
  late final _label = TextEditingController(text: widget.initial?.label);
  late final _year = TextEditingController(
    text: widget.initial?.year?.toString(),
  );
  late final _mileage = TextEditingController(
    text: widget.initial?.mileageKm.toString(),
  );

  @override
  void dispose() {
    _plate.dispose();
    _label.dispose();
    _year.dispose();
    _mileage.dispose();
    super.dispose();
  }

  void _submit() {
    final plate = _plate.text.trim();
    final label = _label.text.trim();
    final year = int.tryParse(_year.text.trim());
    final mileage = int.tryParse(_mileage.text.trim().replaceAll('.', ''));
    final error = _validate(plate, label, year, mileage);
    if (error != null) {
      showApiError(context, error);
      return;
    }
    Navigator.pop<LocalBike>(
      context,
      LocalBike(
        id: widget.initial?.id,
        plate: plate,
        label: label,
        year: year,
        mileageKm: mileage ?? 0,
      ),
    );
  }

  String? _validate(String plate, String label, int? year, int? mileage) {
    if (!isValidPlate(plate)) return 'Placa inválida. Use ABC1234 ou ABC1D23.';
    if (label.isEmpty) return 'Informe a marca e o modelo da moto.';
    final lastYear = DateTime.now().year + 1;
    if (_year.text.trim().isNotEmpty &&
        (year == null || year < 1900 || year > lastYear)) {
      return 'Ano inválido.';
    }
    if (_mileage.text.trim().isNotEmpty && (mileage == null || mileage < 0)) {
      return 'Quilometragem inválida.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      title: widget.initial == null ? 'Adicionar moto' : 'Editar moto',
      onSubmit: _submit,
      children: [
        MtField(
          key: const Key('adicionar-moto-placa'),
          label: 'Placa',
          hint: 'ABC1D23',
          mono: true,
          controller: _plate,
          textCapitalization: TextCapitalization.characters,
        ),
        const SizedBox(height: 14),
        MtField(
          key: const Key('adicionar-moto-modelo'),
          label: 'Marca e modelo',
          hint: 'Honda CG 160 Start',
          controller: _label,
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: MtField(
                key: const Key('adicionar-moto-ano'),
                label: 'Ano',
                hint: '2022',
                controller: _year,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MtField(
                key: const Key('adicionar-moto-km'),
                label: 'Quilometragem',
                hint: '18420',
                controller: _mileage,
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const MtFootnote(
          'Sem conta, a moto fica salva neste aparelho. Reivindicar a '
          'propriedade — e receber os registros das oficinas — exige entrar.',
        ),
      ],
    );
  }
}

class _DialogFrame extends StatelessWidget {
  const _DialogFrame({
    required this.title,
    required this.onSubmit,
    required this.children,
  });

  final String title;
  final VoidCallback onSubmit;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(MtSizes.screenPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            ...children,
            const SizedBox(height: 20),
            ElevatedButton(
              key: const Key('adicionar-moto-continuar'),
              onPressed: onSubmit,
              child: const Text('Continuar'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}
