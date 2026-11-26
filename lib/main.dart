import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';

Future<void> main() async {
  // Lo primero: que el motor de Flutter quede listo. La interfaz se monta
  // a continuacion (sin esperas de red) y el arranque real se muestra en la
  // pantalla de inicio.
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);

  runApp(const MercamigoApp());
}
