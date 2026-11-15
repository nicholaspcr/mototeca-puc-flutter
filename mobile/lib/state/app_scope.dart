import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../demo/demo_client.dart';
import '../models/owner.dart';
import '../models/workshop.dart';
import '../repositories/owner_repository.dart';
import '../repositories/service_record_repository.dart';
import '../repositories/vehicle_repository.dart';
import '../repositories/workshop_repository.dart';
import '../storage/database.dart';
import '../storage/garage_store.dart';
import '../storage/outbox_store.dart';
import '../storage/session_store.dart';

/// The session (workshop or owner), the repositories and the device stores.
class AppState extends ChangeNotifier {
  AppState({ApiClient? client, AppDatabase? database, this._sessions})
    : _client = client ?? createApiClient(),
      _database = database ?? AppDatabase() {
    _client.onUnauthenticated = _expireSession;
    workshops = WorkshopRepository(_client);
    owners = OwnerRepository(_client);
    vehicles = VehicleRepository(_client);
    serviceRecords = ServiceRecordRepository(_client);
    garage = LocalGarage(_database);
    outbox = Outbox(_database);
  }

  final ApiClient _client;
  final AppDatabase _database;

  /// Null keeps the session in memory only, as the demo and the tests do.
  final SessionStore? _sessions;

  late final WorkshopRepository workshops;
  late final OwnerRepository owners;
  late final VehicleRepository vehicles;
  late final ServiceRecordRepository serviceRecords;

  /// The rider's bikes on this device, used by the Motociclista app.
  late final LocalGarage garage;

  /// Records waiting to be published, used by the Oficina app.
  late final Outbox outbox;

  Workshop? _workshop;
  Owner? _owner;
  bool _sessionExpired = false;

  /// Set when the server rejected a token we were holding. The app watches it
  /// to send the user back to login; [acknowledgeExpiry] clears it.
  bool get sessionExpired => _sessionExpired;

  void _expireSession() {
    if (!isSignedIn) return;
    signOut();
    _sessionExpired = true;
    notifyListeners();
  }

  void acknowledgeExpiry() => _sessionExpired = false;

  Workshop? get workshop => _workshop;

  Owner? get owner => _owner;

  bool get isSignedIn => _workshop != null || _owner != null;

  /// Signs back in with the session saved on the last launch, if it has not
  /// expired. A workshop's queue goes out right away, as on a fresh sign-in.
  Future<void> restoreSession() async {
    final sessions = _sessions;
    if (sessions == null || isSignedIn) return;
    final workshop = await sessions.loadWorkshop();
    if (workshop != null) {
      _useWorkshop(workshop);
      await outbox.flush(serviceRecords);
      return;
    }
    final owner = await sessions.loadOwner();
    if (owner != null) _useOwner(owner);
  }

  /// Stores a workshop session and puts its token on every later request.
  void signIn(WorkshopSession session) {
    _useWorkshop(session);
    _sessions?.saveWorkshop(session);
  }

  /// Signing in as one kind clears the other, so a stale token is never sent.
  void signInAsOwner(OwnerSession session) {
    _useOwner(session);
    _sessions?.saveOwner(session);
  }

  void _useWorkshop(WorkshopSession session) {
    _workshop = session.workshop;
    _owner = null;
    _client.authToken = session.token;
    notifyListeners();
  }

  void _useOwner(OwnerSession session) {
    _owner = session.owner;
    _workshop = null;
    _client.authToken = session.token;
    notifyListeners();
  }

  void signOut() {
    _workshop = null;
    _owner = null;
    _client.authToken = null;
    _sessions?.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    garage.dispose();
    outbox.dispose();
    _database.close();
    _client.close();
    super.dispose();
  }
}

/// Exposes [AppState] to the widget tree: `AppScope.of(context)`.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope found — wrap the app in one.');
    return scope!.notifier!;
  }

  /// Reads the state without subscribing, for callbacks that only act on it.
  static AppState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope found — wrap the app in one.');
    return scope!.notifier!;
  }
}
