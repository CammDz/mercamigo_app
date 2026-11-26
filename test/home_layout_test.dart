import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercamigo_app/data/local/key_value_store.dart';
import 'package:mercamigo_app/repositories/cart_repository.dart';
import 'package:mercamigo_app/repositories/catalog_repository.dart';
import 'package:mercamigo_app/services/auth_service.dart';
import 'package:mercamigo_app/services/supabase_service.dart';
import 'package:mercamigo_app/state/cart_controller.dart';
import 'package:mercamigo_app/state/origin_controller.dart';
import 'package:mercamigo_app/ui/screens/home_screen.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

/// Measures of the start screen on a real phone.
///
/// The reference device is 1080x2400 px at 480 dpi, i.e. 360x800 dp. The
/// start screen must fit in that space: no vertical scroll and no
/// overscroll ("bounce") when the content already fits.
void main() {
  const Size phone = Size(360, 800);
  const double density = 3.0;

  setUpAll(() async {
    // Las fuentes del prototipo se cargan a mano: sin ellas el entorno de
    // pruebas usa una fuente de reserva con otras métricas y la medición del
    // layout no sería comparable con la del móvil.
    for (final MapEntry<String, String> font in <String, String>{
      'Jaro': 'assets/fonts/Jaro-Variable.ttf',
      'LeagueSpartan': 'assets/fonts/LeagueSpartan-Variable.ttf',
    }.entries) {
      final FontLoader loader = FontLoader(font.key);
      loader.addFont(rootBundle.load(font.value));
      await loader.load();
    }
  });

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = phone * density;
    tester.view.devicePixelRatio = density;
    addTearDown(tester.view.reset);

    final KeyValueStore store = InMemoryStore();
    final CatalogRepository catalog = CatalogRepository(store: store);
    final CartRepository cart = CartRepository(store);

    await tester.pumpWidget(
      MultiProvider(
        providers: <SingleChildWidget>[
          Provider<SupabaseService>.value(
            value: const SupabaseService(
              client: null,
              status: SupabaseStatus.disabled,
            ),
          ),
          ChangeNotifierProvider<AuthService>.value(
            value: AuthService(null),
          ),
          Provider<CatalogRepository>.value(value: catalog),
          ChangeNotifierProvider<CartController>.value(
            value: CartController(
              cartRepository: cart,
              catalogRepository: catalog,
            ),
          ),
          ChangeNotifierProvider<OriginController>.value(
            value: OriginController(cartRepository: cart),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('El inicio cabe en el móvil: no hay nada que desplazar',
      (WidgetTester tester) async {
    await pumpHome(tester);

    final ScrollableState scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    final ScrollPosition position = scrollable.position;

    // Si el contenido cabe, no hay recorrido: ni scroll ni rebote.
    expect(
      position.maxScrollExtent,
      0,
      reason: 'El inicio sigue desplazándose: el contenido no cabe en '
          '${phone.height} dp de alto.',
    );
  });

  testWidgets('El inicio no tiene desbordamiento (overflow)',
      (WidgetTester tester) async {
    await pumpHome(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Arrastrar el inicio no mueve el contenido',
      (WidgetTester tester) async {
    await pumpHome(tester);

    final Finder logo = find.byType(HomeScreen);
    final double antes = tester.getTopLeft(logo).dy;

    await tester.drag(find.byType(HomeScreen), const Offset(0, 220));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(logo).dy, antes);
  });

  testWidgets('El panel no tiembla: la posición es estable entre fotogramas',
      (WidgetTester tester) async {
    await pumpHome(tester);

    // Si el panel se reconstruye continuamente (el bucle de medición), el
    // contenido se mueve de un fotograma a otro.
    final List<double> posiciones = <double>[];
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      posiciones.add(tester.getTopLeft(find.text('MERCAMIGO')).dy);
    }

    expect(
      posiciones.toSet().length,
      1,
      reason: 'El contenido se mueve entre fotogramas: el panel tiembla. '
          'Posiciones: $posiciones',
    );
  });

  testWidgets('En una pantalla pequeña el contenido sigue siendo accesible',
      (WidgetTester tester) async {
    // Pantalla corta: aquí sí debe poder desplazarse para no cortar nada.
    tester.view.physicalSize = const Size(320, 480) * density;
    tester.view.devicePixelRatio = density;
    addTearDown(tester.view.reset);

    final KeyValueStore store = InMemoryStore();
    final CatalogRepository catalog = CatalogRepository(store: store);
    final CartRepository cart = CartRepository(store);

    await tester.pumpWidget(
      MultiProvider(
        providers: <SingleChildWidget>[
          Provider<SupabaseService>.value(
            value: const SupabaseService(
              client: null,
              status: SupabaseStatus.disabled,
            ),
          ),
          ChangeNotifierProvider<AuthService>.value(
            value: AuthService(null),
          ),
          Provider<CatalogRepository>.value(value: catalog),
          ChangeNotifierProvider<CartController>.value(
            value: CartController(
              cartRepository: cart,
              catalogRepository: catalog,
            ),
          ),
          ChangeNotifierProvider<OriginController>.value(
            value: OriginController(cartRepository: cart),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Se puede desplazar: el botón de abajo sigue siendo accesible.
    final ScrollableState scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));

    await tester.drag(find.byType(HomeScreen), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(0));
  });
}
