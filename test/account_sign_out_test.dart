import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercamigo_app/data/local/key_value_store.dart';
import 'package:mercamigo_app/repositories/cart_repository.dart';
import 'package:mercamigo_app/repositories/catalog_repository.dart';
import 'package:mercamigo_app/repositories/order_repository.dart';
import 'package:mercamigo_app/repositories/profile_repository.dart';
import 'package:mercamigo_app/repositories/scan_history_repository.dart';
import 'package:mercamigo_app/repositories/settings_repository.dart';
import 'package:mercamigo_app/services/auth_service.dart';
import 'package:mercamigo_app/state/cart_controller.dart';
import 'package:mercamigo_app/state/order_controller.dart';
import 'package:mercamigo_app/state/order_history_controller.dart';
import 'package:mercamigo_app/ui/screens/my_account_screen.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

/// Pruebas del cierre de sesion desde "Mi cuenta".
///
/// El cierre debe:
///
/// * mandar al login **de inmediato**, sin esperar a que el servidor
///   revoque el token;
/// * no fallar por proveedores que no existen (por ejemplo, el repositorio
///   de pedidos, que solo esta dentro del controlador de ordenes).
void main() {
  testWidgets('Cerrar sesion vuelve al login sin errores ni esperas',
      (WidgetTester tester) async {
    final KeyValueStore store = InMemoryStore();
    final CatalogRepository catalog = CatalogRepository(store: store);
    final CartRepository cartRepository = CartRepository(store);
    final OrderRepository orderRepository = OrderRepository(store: store);
    final CartController cart = CartController(
      cartRepository: cartRepository,
      catalogRepository: catalog,
    );
    final OrderController orders = OrderController(
      orderRepository: orderRepository,
      settingsRepository: SettingsRepository(store: store),
    );
    final OrderHistoryController history =
        OrderHistoryController(repository: orderRepository);
    final AuthService auth = AuthService(null);

    await tester.pumpWidget(
      MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<AuthService>.value(value: auth),
          ChangeNotifierProvider<CartController>.value(value: cart),
          ChangeNotifierProvider<OrderController>.value(value: orders),
          ChangeNotifierProvider<OrderHistoryController>.value(value: history),
          Provider<ProfileRepository>.value(
            value: ProfileRepository(client: null),
          ),
          Provider<ScanHistoryRepository>.value(
            value: ScanHistoryRepository(store: store),
          ),
        ],
        child: const MaterialApp(
          home: MyAccountScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // El boton de cerrar sesion esta al final de la pantalla.
    await tester.scrollUntilVisible(
      find.textContaining('Cerrar sesi'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.textContaining('Cerrar sesi'));
    await tester.pump();

    // No debe haber excepciones (por ejemplo, un Provider inexistente).
    expect(tester.takeException(), isNull);

    // Y la sesion local queda cerrada de inmediato.
    expect(auth.status, AuthStatus.signedOut);
  });
}
