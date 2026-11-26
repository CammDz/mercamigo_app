import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercamigo_app/core/theme/app_colors.dart';
import 'package:mercamigo_app/data/local/key_value_store.dart';
import 'package:mercamigo_app/repositories/cart_repository.dart';
import 'package:mercamigo_app/repositories/catalog_repository.dart';
import 'package:mercamigo_app/state/cart_controller.dart';
import 'package:mercamigo_app/ui/widgets/cart_badge_button.dart';
import 'package:provider/provider.dart';

/// El icono del carrito.
///
/// Se usa el icono de Material (no el recurso `assets/figma/icon_cart.png`)
/// porque ese recurso trae el globo con el "1" dibujado. En el escaner
/// (fondo oscuro) se pinta de blanco; en el resto de pantallas, negro.
void main() {
  Future<CartController> controller() async {
    final KeyValueStore store = InMemoryStore();
    final CatalogRepository catalog = CatalogRepository(store: store);
    final CartRepository cart = CartRepository(store);
    return CartController(
      cartRepository: cart,
      catalogRepository: catalog,
    );
  }

  testWidgets('Con tinte blanco el icono se pinta de blanco',
      (WidgetTester tester) async {
    final CartController cart = await controller();
    addTearDown(cart.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<CartController>.value(
        value: cart,
        child: const MaterialApp(
          home: Scaffold(
            body: CartBadgeButton(color: Colors.white, tint: Colors.white),
          ),
        ),
      ),
    );
    await tester.pump();

    final Icon icon = tester.widget<Icon>(find.byIcon(Icons.shopping_cart_outlined));
    expect(icon.color, Colors.white);
  });

  testWidgets('Sin tinte el icono conserva su color original',
      (WidgetTester tester) async {
    final CartController cart = await controller();
    addTearDown(cart.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<CartController>.value(
        value: cart,
        child: const MaterialApp(
          home: Scaffold(body: CartBadgeButton()),
        ),
      ),
    );
    await tester.pump();

    final Icon icon = tester.widget<Icon>(find.byIcon(Icons.shopping_cart_outlined));
    expect(icon.color, AppColors.ink);
  });

  testWidgets('El icono no usa el recurso con el globo dibujado',
      (WidgetTester tester) async {
    final CartController cart = await controller();
    addTearDown(cart.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<CartController>.value(
        value: cart,
        child: const MaterialApp(
          home: Scaffold(body: CartBadgeButton()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsNothing);
  });
}
