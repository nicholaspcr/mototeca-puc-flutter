import 'package:flutter/material.dart';

import '../models/service_record.dart';
import '../rider/garage_screen.dart';
import '../rider/owner_register_screen.dart';
import '../rider/reminders_screen.dart';
import '../rider/rider_home_screen.dart';
import '../rider/rider_sign_in_screen.dart';
import '../shared/about_screen.dart';
import '../shared/plate_lookup_screen.dart';
import '../shared/service_detail_screen.dart';
import '../shared/vehicle_register_screen.dart';
import '../shop/dashboard_screen.dart';
import '../shop/new_record_screen.dart';
import '../shop/outbox_screen.dart';
import '../shop/shop_home_screen.dart';
import '../shop/shop_sign_in_screen.dart';
import '../shop/workshop_register_screen.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import 'flavor.dart';
import 'routes.dart';

/// Either of the two apps, chosen by the entry point that builds it:
/// `lib/main_rider.dart` or `lib/main_shop.dart`.
class MototecaApp extends StatefulWidget {
  const MototecaApp({super.key, required this.flavor, this.state});

  final AppFlavor flavor;

  /// Injected by tests so they can supply a fake backend.
  final AppState? state;

  @override
  State<MototecaApp> createState() => _MototecaAppState();
}

class _MototecaAppState extends State<MototecaApp> {
  late final AppState _state = widget.state ?? AppState();
  late final bool _ownsState = widget.state == null;
  final _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _state.addListener(_onStateChanged);
  }

  /// A session can expire on any request, including ones a FutureBuilder
  /// never catches. Home, not a login: home works signed out.
  void _onStateChanged() {
    if (!_state.sessionExpired) return;
    _state.acknowledgeExpiry();
    _navigator.currentState?.pushNamedAndRemoveUntil(Routes.home, (_) => false);
  }

  @override
  void dispose() {
    _state.removeListener(_onStateChanged);
    // Only close the client this widget created; an injected one belongs to
    // whoever passed it in.
    if (_ownsState) _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppFlavorScope(
      flavor: widget.flavor,
      child: AppScope(state: _state, child: _buildApp()),
    );
  }

  Widget _buildApp() {
    return MaterialApp(
      navigatorKey: _navigator,
      title: widget.flavor.title,
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
      initialRoute: Routes.home,
      routes: switch (widget.flavor) {
        AppFlavor.rider => _riderRoutes,
        AppFlavor.shop => _shopRoutes,
      },
      onGenerateRoute: _onGenerateRoute,
    );
  }

  /// App Motociclista — see design/NAVIGATION.md.
  static final _riderRoutes = <String, WidgetBuilder>{
    Routes.home: (_) => const RiderHomeScreen(),
    Routes.signIn: (_) => const RiderSignInScreen(),
    Routes.signUp: (_) => const OwnerRegisterScreen(),
    Routes.garage: (_) => const GarageScreen(),
    Routes.reminders: (_) => const RemindersScreen(),
    Routes.about: (_) => const AboutScreen(),
  };

  /// App Oficina — see design/NAVIGATION.md.
  static final _shopRoutes = <String, WidgetBuilder>{
    Routes.home: (_) => const ShopHomeScreen(),
    Routes.signIn: (_) => const ShopSignInScreen(),
    Routes.signUp: (_) => const WorkshopRegisterScreen(),
    Routes.dashboard: (_) => const DashboardScreen(),
    Routes.outbox: (_) => const OutboxScreen(),
    Routes.about: (_) => const AboutScreen(),
  };

  /// Routes that carry an argument; everything else is in the tables above.
  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    final shopOnly = widget.flavor.isShop;
    return switch (settings.name) {
      Routes.serviceDetail => MaterialPageRoute<void>(
        builder: (_) =>
            ServiceDetailScreen(args: settings.arguments as ServiceDetailArgs),
        settings: settings,
      ),
      // Both optionally arrive with a plate already typed elsewhere.
      Routes.plateLookup => MaterialPageRoute<void>(
        builder: (_) =>
            PlateLookupScreen(initialPlate: settings.arguments as String?),
        settings: settings,
      ),
      Routes.vehicleRegister => MaterialPageRoute<void>(
        builder: (_) =>
            VehicleRegisterScreen(initialPlate: settings.arguments as String?),
        settings: settings,
      ),
      Routes.newRecord when shopOnly => MaterialPageRoute<void>(
        builder: (_) =>
            NewRecordScreen(initialPlate: settings.arguments as String?),
        settings: settings,
      ),
      Routes.reviseRecord when shopOnly => MaterialPageRoute<void>(
        builder: (_) =>
            NewRecordScreen(revising: settings.arguments as ServiceRecord),
        settings: settings,
      ),
      _ => null,
    };
  }
}
