import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../models/owner.dart';
import '../models/workshop.dart';
import '../repositories/owner_repository.dart';
import '../repositories/service_record_repository.dart';
import '../repositories/vehicle_repository.dart';
import '../repositories/workshop_repository.dart';

/// Holds the signed-in account and the repositories the screens call.
///
/// A plain [ChangeNotifier] rather than a state-management package: the app
/// has one piece of shared state, and a dependency would cost more than it
/// saves. A session is a workshop or an owner, never both.
class AppState extends ChangeNotifier {
  AppState({ApiClient? client}) : _client = client ?? ApiClient() {
    _client.onUnauthenticated = _expireSession;
    workshops = WorkshopRepository(_client);
    owners = OwnerRepository(_client);
    vehicles = VehicleRepository(_client);
    serviceRecords = ServiceRecordRepository(_client);
  }

  final ApiClient _client;

  late final WorkshopRepository workshops;
  late final OwnerRepository owners;
  late final VehicleRepository vehicles;
  late final ServiceRecordRepository serviceRecords;

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
