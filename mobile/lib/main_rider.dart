import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/flavor.dart';

/// Entry point of the Mototeca Motociclista app.
///
///   flutter run -t lib/main_rider.dart
void main() => runApp(const MototecaApp(flavor: AppFlavor.rider));
