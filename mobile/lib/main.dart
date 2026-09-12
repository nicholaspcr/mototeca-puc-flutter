import 'package:flutter/material.dart';

import 'screens/about_screen.dart';
import 'screens/customer_portal_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/my_vehicles_screen.dart';
import 'screens/new_record_screen.dart';
import 'screens/reminders_screen.dart';
import 'screens/service_detail_screen.dart';
import 'screens/vehicle_register_screen.dart';
import 'screens/workshop_register_screen.dart';
import 'state/app_scope.dart';
import 'theme.dart';

void main() => runApp(const MototecaApp());

/// Route names — mirrors design/NAVIGATION.md.
class Routes {
  static const login = '/';
  static const workshopRegister = '/oficina/cadastro';
  static const dashboard = '/oficina';
  static const newRecord = '/oficina/registro/novo';
  static const vehicleRegister = '/veiculo/cadastro';
  static const myVehicles = '/proprietario';
  static const reminders = '/proprietario/lembretes';
  static const customerPortal = '/consulta';
  static const serviceDetail = '/servico';
  static const about = '/sobre';
}

class MototecaApp extends StatefulWidget {
  const MototecaApp({super.key, this.state});

  /// Injected by tests so they can supply a fake backend.
  final AppState? state;

  @override
  State<MototecaApp> createState() => _MototecaAppState();
}

class _MototecaAppState extends State<MototecaApp> {
  late final AppState _state = widget.state ?? AppState();
  late final bool _ownsState = widget.state == null;

  @override
  void dispose() {
    // Only close the client this widget created; an injected one belongs to
    // whoever passed it in.
    if (_ownsState) _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(state: _state, child: _buildApp(context));
  }

  Widget _buildApp(BuildContext context) {
    return MaterialApp(
      title: 'Mototeca',
      debugShowCheckedModeBanner: false,
      theme: buildMototecaTheme(),
      // Keeps the app phone-shaped (iPhone 15 Pro width) when demoed in a
      // desktop browser; a no-op on a real phone, which is already narrower.
      builder: (context, child) => ColoredBox(
        color: const Color(0xFFE9EEF3),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 393),
            child: child,
          ),
        ),
      ),
      initialRoute: Routes.login,
      routes: {
        Routes.login: (_) => const LoginScreen(),
        Routes.workshopRegister: (_) => const WorkshopRegisterScreen(),
        Routes.dashboard: (_) => const DashboardScreen(),
        Routes.myVehicles: (_) => const MyVehiclesScreen(),
        Routes.reminders: (_) => const RemindersScreen(),
        Routes.customerPortal: (_) => const CustomerPortalScreen(),
        Routes.about: (_) => const AboutScreen(),
      },
      // Routes that carry an argument. Everything else is in `routes` above.
      onGenerateRoute: (settings) => switch (settings.name) {
        Routes.serviceDetail => MaterialPageRoute(
          builder: (_) => ServiceDetailScreen(
            args: settings.arguments as ServiceDetailArgs,
          ),
          settings: settings,
        ),
        // Both optionally arrive with a plate already typed elsewhere.
        Routes.newRecord => MaterialPageRoute(
          builder: (_) =>
              NewRecordScreen(initialPlate: settings.arguments as String?),
          settings: settings,
        ),
        Routes.vehicleRegister => MaterialPageRoute(
          builder: (_) =>
              VehicleRegisterScreen(initialPlate: settings.arguments as String?),
          settings: settings,
        ),
        _ => null,
      },
    );
  }
}
