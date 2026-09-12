import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../models/workshop.dart';
import '../repositories/service_record_repository.dart';
import '../repositories/vehicle_repository.dart';
import '../repositories/workshop_repository.dart';

/// Holds the signed-in workshop and the repositories the screens call.
///
/// Deliberately a plain [ChangeNotifier] behind an [InheritedNotifier] rather
/// than a state-management package: the app has exactly one piece of shared
/// state (the session), and a dependency would cost more than it saves.
class AppState extends ChangeNotifier {
  AppState({ApiClient? client}) : _client = client ?? ApiClient() {
    workshops = WorkshopRepository(_client);
    vehicles = VehicleRepository(_client);
    serviceRecords = ServiceRecordRepository(_client);
  }

  final ApiClient _client;

  late final WorkshopRepository workshops;
  late final VehicleRepository vehicles;
  late final ServiceRecordRepository serviceRecords;

  Workshop? _workshop;

  /// The signed-in oficina, or null when nobody is signed in.
  Workshop? get workshop => _workshop;
  bool get isSignedIn => _workshop != null;

  /// Stores the session and puts its token on every later request.
  void signIn(WorkshopSession session) {
    _workshop = session.workshop;
    _client.authToken = session.token;
    notifyListeners();
  }

  void signOut() {
    _workshop = null;
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
