import 'package:flutter_test/flutter_test.dart';
import 'package:mercamigo_app/data/local/key_value_store.dart';
import 'package:mercamigo_app/data/models/cart_item.dart';
import 'package:mercamigo_app/core/utils/order_number.dart';
import 'package:mercamigo_app/data/models/order.dart';
import 'package:mercamigo_app/data/models/product.dart';
import 'package:mercamigo_app/data/models/purchase_origin.dart';
import 'package:mercamigo_app/repositories/cart_repository.dart';
import 'package:mercamigo_app/repositories/catalog_repository.dart';
import 'package:mercamigo_app/repositories/order_repository.dart';
import 'package:mercamigo_app/repositories/settings_repository.dart';
import 'package:mercamigo_app/services/order_code_service.dart';
import 'package:mercamigo_app/state/cart_controller.dart';
import 'package:mercamigo_app/state/order_controller.dart';

import 'helpers/catalog_fixtures.dart';

Future<OrderController> buildOrderController(
  InMemoryStore store, {
  OrderGateway? gateway,
}) async {
  return OrderController(
    orderRepository: OrderRepository(store: store, gateway: gateway),
    settingsRepository: SettingsRepository(store: store),
  );
}

void main() {
  group('Guardado del pedido', () {
    test('guarda el pedido con todos los datos requeridos', () async {
      final InMemoryStore store = InMemoryStore();
      final OrderController controller = await buildOrderController(store);
      final CatalogRepository catalog = await CatalogFixtures.buildRepository();
      final Product product = catalog.all.first;

      final Order? order = await controller.createOrder(
        items: <CartItem>[CartItem.fromProduct(product, quantity: 2)],
        origin: PurchaseOrigin.inStore,
        createdAt: DateTime(2026, 10, 20, 10, 30),
      );

      expect(order, isNotNull);
      expect(order!.id, isNotEmpty);
      expect(order.orderNumber, isNotEmpty);
      // El modelo guarda el instante en UTC: el momento es exactamente el
      // que se pidio, solo cambia como se expresa.
      expect(order.createdAt, DateTime(2026, 10, 20, 10, 30).toUtc());
      expect(order.createdAt.toUtc(), DateTime(2026, 10, 20, 10, 30).toUtc());
      expect(order.origin, PurchaseOrigin.inStore);
      expect(order.items.length, 1);
      expect(order.items.first.name, product.name);
      expect(order.items.first.quantity, 2);
      expect(order.items.first.unitPrice, product.price);
      expect(order.total, order.items.first.payableTotal);
      expect(order.status, OrderStatus.pendingPayment);
    });

    test('el pedido se conserva al cerrar y abrir la app', () async {
      final InMemoryStore store = InMemoryStore();
      final OrderController controller = await buildOrderController(store);
      final CatalogRepository catalog = await CatalogFixtures.buildRepository();

      final Order? created = await controller.createOrder(
        items: <CartItem>[CartItem.fromProduct(catalog.all.first)],
        origin: PurchaseOrigin.pickup,
      );
      expect(created, isNotNull);

      // Nueva instancia de la app: el pedido sigue ahí.
      final OrderController reloaded = await buildOrderController(store);
      await reloaded.load();

      expect(reloaded.orders.length, 1);
      expect(reloaded.orders.first.id, created!.id);
      expect(reloaded.orders.first.orderNumber, created.orderNumber);
      expect(reloaded.orders.first.total, created.total);
    });

    test('los números de orden no se repiten', () async {
      final InMemoryStore store = InMemoryStore();
      final OrderController controller = await buildOrderController(store);
      final CatalogRepository catalog = await CatalogFixtures.buildRepository();
      final List<CartItem> items = <CartItem>[
        CartItem.fromProduct(catalog.all.first),
      ];

      final Set<String> numbers = <String>{};
      for (int i = 0; i < 5; i++) {
        final Order? order = await controller.createOrder(
          items: items,
          origin: PurchaseOrigin.inStore,
        );
        expect(order, isNotNull);
        expect(numbers.add(order!.orderNumber), isTrue,
            reason: 'El número ${order.orderNumber} ya existía');
      }
      expect(numbers.length, 5);
    });

    test('una pulsación repetida no genera dos pedidos', () async {
      final InMemoryStore store = InMemoryStore();
      final OrderController controller = await buildOrderController(store);
      final CatalogRepository catalog = await CatalogFixtures.buildRepository();
      final List<CartItem> items = <CartItem>[
        CartItem.fromProduct(catalog.all.first),
      ];

      final List<Order?> results = await Future.wait<Order?>(<Future<Order?>>[
        controller.createOrder(items: items, origin: PurchaseOrigin.inStore),
        controller.createOrder(items: items, origin: PurchaseOrigin.inStore),
      ]);

      final int guardados =
          results.where((Order? order) => order != null).length;
      expect(guardados, 1);
      expect(controller.orders.length, 1);
    });

    test('no se crea un pedido sin productos', () async {
      final InMemoryStore store = InMemoryStore();
      final OrderController controller = await buildOrderController(store);

      final Order? order = await controller.createOrder(
        items: const <CartItem>[],
        origin: PurchaseOrigin.inStore,
      );

      expect(order, isNull);
      expect(controller.orders, isEmpty);
    });

    test('el carrito no se borra si el guardado del pedido falla', () async {
      final InMemoryStore store = InMemoryStore();
      final CatalogRepository catalog = await CatalogFixtures.buildRepository();
      final CartController cart = CartController(
        cartRepository: CartRepository(store),
        catalogRepository: catalog,
      );      await cart.add(catalog.all.first, quantity: 3);

      final OrderController controller = OrderController(
        orderRepository: OrderRepository(
          store: store,
          gateway: _FailingOrderGateway(),
        ),
        settingsRepository: SettingsRepository(store: store),
      );

      Order? order;
      try {
        order = await controller.createOrder(
          items: cart.items,
          origin: PurchaseOrigin.inStore,
        );
      } catch (_) {
        order = null;
      }

      expect(order, isNull);
      // El carrito sigue intacto porque el guardado no fue exitoso.
      expect(cart.items.length, 1);
      expect(cart.items.first.quantity, 3);
    });
  });

  group('Coherencia entre el identificador del pedido y el código QR', () {
    test('el QR local usa exactamente el número visible', () async {
      final InMemoryStore store = InMemoryStore();
      final OrderController controller = await buildOrderController(store);
      final CatalogRepository catalog = await CatalogFixtures.buildRepository();

      final Order? order = await controller.createOrder(
        items: <CartItem>[CartItem.fromProduct(catalog.all.first, quantity: 2)],
        origin: PurchaseOrigin.inStore,
      );

      expect(order, isNotNull);
      const OrderCodeService codeService = OrderCodeService();
      final Order created = order!;
      expect(codeService.buildOrderPayload(created), created.orderNumber);
      expect(created.qrPayload, created.orderNumber);
    });

    test('el número del código es el que quedó guardado', () async {
      final InMemoryStore store = InMemoryStore();
      final OrderController controller = await buildOrderController(store);
      final CatalogRepository catalog = await CatalogFixtures.buildRepository();

      final Order? order = await controller.createOrder(
        items: <CartItem>[CartItem.fromProduct(catalog.all.first)],
        origin: PurchaseOrigin.pickup,
      );

      final String payload = const OrderCodeService().buildOrderPayload(order!);

      final OrderController reloaded = await buildOrderController(store);
      await reloaded.load();

      final Order stored = reloaded.orders
          .firstWhere((Order item) => item.orderNumber == payload);
      expect(stored.id, order.id);
      expect(stored.orderNumber, order.orderNumber);
    });

    test('con servidor, el QR usa el identificador del pedido', () async {
      final InMemoryStore store = InMemoryStore();
      final _FakeGateway gateway = _FakeGateway();
      final OrderController controller = await buildOrderController(
        store,
        gateway: gateway,
      );
      final CatalogRepository catalog = await CatalogFixtures.buildRepository();

      final Order? order = await controller.createOrder(
        items: <CartItem>[CartItem.fromProduct(catalog.all.first)],
        origin: PurchaseOrigin.inStore,
        storeId: 'tienda-uuid-1',
      );

      expect(order, isNotNull);
      expect(order!.isServerOrder, isTrue);
      // El QR identifica el pedido en el servidor; el número sigue visible
      // para la búsqueda manual del personal de caja.
      expect(order.qrPayload, order.id);
      expect(
        const OrderCodeService().buildOrderPayload(order),
        order.id,
      );
      expect(order.orderNumber, isNotEmpty);
    });

    test('cada orden tiene un identificador interno único', () async {
      final InMemoryStore store = InMemoryStore();
      final OrderController controller = await buildOrderController(store);
      final CatalogRepository catalog = await CatalogFixtures.buildRepository();
      final List<CartItem> items = <CartItem>[
        CartItem.fromProduct(catalog.all.first),
      ];

      final Set<String> ids = <String>{};
      for (int i = 0; i < 10; i++) {
        final Order? order = await controller.createOrder(
          items: items,
          origin: PurchaseOrigin.inStore,
        );
        expect(order, isNotNull);
        expect(ids.add(order!.id), isTrue);
      }
    });
  });
}

/// Gateway que siempre falla (para probar que el carrito no se borra).
class _FailingOrderGateway implements OrderGateway {
  @override
  bool get isAvailable => true;

  @override
  Future<Order> createOrder({
    required List<CartItem> items,
    required PurchaseOrigin origin,
    required String idempotencyKey,
    required String storeId,
  }) async {
    throw StateError('Fallo simulado al guardar la orden');
  }
}

/// Gateway de mentira que devuelve una orden de servidor.
class _FakeGateway implements OrderGateway {
  @override
  bool get isAvailable => true;

  @override
  Future<Order> createOrder({
    required List<CartItem> items,
    required PurchaseOrigin origin,
    required String idempotencyKey,
    required String storeId,
  }) async {
    final CartItem item = items.first;
    return Order(
      id: 'pedido-uuid-1',
      orderNumber: formatOrderNumber(1),
      numeroOrden: 1,
      createdAt: DateTime.now(),
      origin: origin,
      items: <OrderItem>[
        OrderItem(
          productId: item.productId,
          name: item.name,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          subtotal: item.payableTotal,
        ),
      ],
      subtotal: item.payableTotal,
      total: item.payableTotal,
      status: OrderStatus.pendingPayment,
      isServerOrder: true,
    );
  }
}
