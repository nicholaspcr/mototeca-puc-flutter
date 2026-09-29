import 'package:flutter/material.dart';

import '../theme.dart';

/// Which of the two apps this binary is. One codebase, two entry points:
/// `lib/main_rider.dart` and `lib/main_shop.dart` (design/NAVIGATION.md).
enum AppFlavor {
  rider(
    title: 'Mototeca Motociclista',
    badge: 'Motociclista',
    badgeColor: MtColors.petrol,
    otherApp: 'Mototeca Oficina',
  ),
  shop(
    title: 'Mototeca Oficina',
    badge: 'Oficina',
    badgeColor: MtColors.rust,
    otherApp: 'Mototeca Motociclista',
  );

  const AppFlavor({
    required this.title,
    required this.badge,
    required this.badgeColor,
    required this.otherApp,
  });

  final String title;

  /// Shown on every screen header.
  final String badge;

  final Color badgeColor;

  /// Pointed at from the home screen, for someone on the wrong app.
  final String otherApp;

  bool get isRider => this == AppFlavor.rider;
  bool get isShop => this == AppFlavor.shop;
}

/// `AppFlavorScope.of(context)`. Only the shared screens read it, to label
/// themselves; a screen that needs a different layout per app is two screens.
class AppFlavorScope extends InheritedWidget {
  const AppFlavorScope({
    super.key,
    required this.flavor,
    required super.child,
  });

  final AppFlavor flavor;

  static AppFlavor of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppFlavorScope>();
    assert(scope != null, 'No AppFlavorScope found — wrap the app in one.');
    return scope!.flavor;
  }

  @override
  bool updateShouldNotify(AppFlavorScope oldWidget) =>
      oldWidget.flavor != flavor;
}
