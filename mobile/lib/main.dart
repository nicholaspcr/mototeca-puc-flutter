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

class MototecaApp extends StatelessWidget {
  const MototecaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mototeca',
      debugShowCheckedModeBanner: false,
      theme: buildMototecaTheme(),
      initialRoute: Routes.login,
      routes: {
        Routes.login: (_) => const LoginScreen(),
        Routes.workshopRegister: (_) => const WorkshopRegisterScreen(),
        Routes.dashboard: (_) => const DashboardScreen(),
        Routes.newRecord: (_) => const NewRecordScreen(),
        Routes.vehicleRegister: (_) => const VehicleRegisterScreen(),
        Routes.myVehicles: (_) => const MyVehiclesScreen(),
        Routes.reminders: (_) => const RemindersScreen(),
        Routes.customerPortal: (_) => const CustomerPortalScreen(),
        Routes.about: (_) => const AboutScreen(),
      },
      onGenerateRoute: (settings) {
        // /servico/:id carries the record it should display.
        if (settings.name == Routes.serviceDetail) {
          final args = settings.arguments as ServiceDetailArgs;
          return MaterialPageRoute(
            builder: (_) => ServiceDetailScreen(args: args),
            settings: settings,
          );
        }
        return null;
      },
    );
  }
}
