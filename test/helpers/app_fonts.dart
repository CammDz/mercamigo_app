import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Carga las fuentes del prototipo en el entorno de pruebas.
///
/// Sin ellas, el entorno de pruebas usa una fuente de reserva con métricas
/// muy distintas (alturas de línea casi tres veces mayores) y cualquier
/// medición de layout sería falsa: en el móvil el texto ocupa much menos.
Future<void> loadAppFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final MapEntry<String, String> font in <String, String>{
    'Jaro': 'assets/fonts/Jaro-Variable.ttf',
    'LeagueSpartan': 'assets/fonts/LeagueSpartan-Variable.ttf',
  }.entries) {
    final FontLoader loader = FontLoader(font.key);
    loader.addFont(rootBundle.load(font.value));
    await loader.load();
  }
}
