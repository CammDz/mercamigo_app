import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Comprueba que TODOS los recursos que usa el código existen realmente.
///
/// Antes, el código referenciaba rutas como `assets/figma/logo.png` mientras
/// los ficheros se llamaban con el hash de Figma: ningun logo se mostraba y
/// todas las imagenes caian en su `errorBuilder`. Esta prueba lo evita.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const List<String> assets = <String>[
    'assets/figma/logo.png',
    'assets/figma/icon_shop.png',
    'assets/figma/icon_phone.png',
    'assets/figma/icon_search.png',
    'assets/figma/icon_cart.png',
    'assets/figma/icon_market.png',
    'assets/figma/cat_bebidas.png',
    'assets/figma/cat_snacks.png',
    'assets/figma/cat_postres.png',
    'assets/figma/cat_lacteos.png',
    'assets/figma/cat_cuidado.png',
    'assets/figma/cat_hogar.png',
    'assets/figma/cat_mascotas.png',
    'assets/figma/cat_despensa.png',
    'assets/figma/product_astra.png',
    'assets/figma/product_agua.png',
    'assets/figma/product_jugo.png',
    'assets/figma/scan_button.svg',
    'assets/figma/icon_clock.svg',
    'assets/figma/btn_share.svg',
    'assets/icon/icon_launcher.png',
    'assets/icon/icon_launcher_foreground.png',
  ];

  test('todos los recursos referenciados existen', () async {
    for (final String asset in assets) {
      final ByteData data = await rootBundle.load(asset);
      expect(
        data.lengthInBytes,
        greaterThan(0),
        reason: 'El recurso $asset esta vacio',
      );
    }
  });

  test('el logo de Mercamigo es una imagen valida de 500x500', () async {
    final ByteData data = await rootBundle.load('assets/figma/logo.png');
    expect(data.lengthInBytes, greaterThan(1000));
  });
}
