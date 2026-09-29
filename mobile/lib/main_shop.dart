import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/flavor.dart';

/// Entry point of the Mototeca Oficina app.
///
///   flutter run -t lib/main_shop.dart
void main() => runApp(const MototecaApp(flavor: AppFlavor.shop));
