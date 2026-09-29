import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../demo/demo_client.dart';
import '../models/owner.dart';
import '../models/workshop.dart';
import '../repositories/owner_repository.dart';
import '../repositories/service_record_repository.dart';
import '../repositories/vehicle_repository.dart';
import '../repositories/workshop_repository.dart';
import '../storage/garage_store.dart';
import '../storage/local_store.dart';
import '../storage/outbox_store.dart';

/// Holds the signed-in account, the repositories the screens call and the two
/// stores that work before any account exists.
///
/// A plain [ChangeNotifier] rather than a state-management package: the app
/// has one piece of shared state, and a dependency would cost more than it
/// saves. A session is a workshop or an owner, never both.
class AppState extends ChangeNotifier {
  AppState({ApiClient? client, LocalStore? store})
    : _client = client ?? createApiClient(),
      _store = store ?? createLocalStore() {
    _client.onUnauthenticated = _expireSession;
    workshops = WorkshopRepository(_client);
    owners = OwnerRepository(_client);
    vehicles = VehicleRepository(_client);
    serviceRecords = ServiceRecordRepository(_client);
    garage = LocalGarage(_store);
    outbox = Outbox(_store);
  }

  final ApiClient _client;
  final LocalStore _store;

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

  /// The signed-in oficina, or null when nobody is signed in as one.
  Workshop? get workshop => _workshop;

  /// The signed-in proprietário, or null.
  Owner? get owner => _owner;

  bool get isSignedIn => _workshop != null || _owner != null;

  /// Stores a workshop session and puts its token on every later request.
  void signIn(WorkshopSession session) {
    _workshop = session.workshop;
    _owner = null;
    _client.authToken = session.token;
    notifyListeners();
  }

  /// Signing in as one kind clears the other, so a stale token is never sent.
  void signInAsOwner(OwnerSession session) {
    _owner = session.owner;
    _workshop = null;
    _client.authToken = session.token;
    notifyListeners();
  }

  void signOut() {
    _workshop = null;
    _owner = null;
    _client.authToken = null;
    notifyListeners();
  }

  @override
  void dispose() {
    garage.dispose();
    outbox.dispose();
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
