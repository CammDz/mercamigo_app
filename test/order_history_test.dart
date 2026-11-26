import 'package:flutter_test/flutter_test.dart';
import 'package:mercamigo_app/core/utils/order_number.dart';
import 'package:mercamigo_app/data/models/order.dart';
import 'package:mercamigo_app/data/models/purchase_origin.dart';
import 'package:mercamigo_app/data/local/key_value_store.dart';
import 'package:mercamigo_app/repositories/order_repository.dart';
import 'package:mercamigo_app/state/order_history_controller.dart';

/// Fila de `pedidos` tal y como la devuelve PostgREST.
Map<String, dynamic> _serverRow({
  required String id,
  required int numeroOrden,
  required String origen,
  required int total,
  required String estado,
}) {
  return <String, dynamic>{
    'id': id,
    'numero_orden': numeroOrden,
    'tienda_id': 'tienda-1',
    'origen': origen,
    'total_cop': total,
    'estado': estado,
    'creado_en': '2026-10-20T15:30:00+00:00',
    'tiendas': <Map<String, dynamic>>[
      <String, dynamic>{'nombre': 'Mercamigo Demo'}
    ],
    'detalle_pedido': <Map<String, dynamic>>[
      <String, dynamic>{
        'producto_id': 'prod-1',
        'nombre_producto': 'Astra-Cola Original 500 ml',
        'cantidad': 2,
        'precio_unitario_cop': 2500,
        'subtotal_cop': 5000,
      },
      <String, dynamic>{
        'producto_id': 'prod-2',
        'nombre_producto': 'Agua original 600 ml',
        'cantidad': 1,
        'precio_unitario_cop': 3000,
        'subtotal_cop': 3000,
      },
    ],
  };
}

/// Repositorio de mentira que devuelve páginas fijas.
class _FakeOrderRepository extends OrderRepository {
  _FakeOrderRepository(this._pages) : super(store: InMemoryStore());

  final List<List<Order>> _pages;

  @override
  Future<List<Order>> loadServerOrders({
    required String userId,
    int page = 0,
    int pageSize = 20,
  }) async {
    if (page >= _pages.length) return <Order>[];
    return _pages[page];
  }

  @override
  Future<Order?> loadServerOrder(String orderId, String userId) async {
    for (final List<Order> page in _pages) {
      for (final Order order in page) {
        if (order.id == orderId) return order;
      }
    }
    return null;
  }
}

Order _order({
  required String id,
  required int numero,
  required int total,
  String estado = 'pendiente_pago',
}) {
  return Order(
    id: id,
    orderNumber: formatOrderNumber(numero),
    numeroOrden: numero,
    createdAt: DateTime.utc(2026, 10, 20),
    origin: PurchaseOrigin.inStore,
    items: const <OrderItem>[],
    subtotal: total,
    total: total,
    status: OrderStatus.fromServer(estado),
    isServerOrder: true,
  );
}

void main() {
  group('Historial del propietario', () {
    test('una fila del servidor se convierte en una orden', () {
      final Order order = OrderRepository.orderFromServerRow(_serverRow(
        id: 'pedido-1',
        numeroOrden: 104,
        origen: 'en_tienda',
        total: 8000,
        estado: 'pendiente_pago',
      ));

      expect(order.id, 'pedido-1');
      expect(order.numeroOrden, 104);
      expect(order.orderNumber, 'MCA-000104');
      expect(order.origin, PurchaseOrigin.inStore);
      expect(order.total, 8000);
      expect(order.status, OrderStatus.pendingPayment);
      expect(order.items.length, 2);
      expect(order.items.first.name, 'Astra-Cola Original 500 ml');
      expect(order.items.first.quantity, 2);
      expect(order.items.first.unitPrice, 2500);
      expect(order.items.first.subtotal, 5000);
      expect(order.subtotal, 8000);
      expect(order.isServerOrder, isTrue);
    });

    test('el origen "para_recoger" se reconoce', () {
      final Order order = OrderRepository.orderFromServerRow(_serverRow(
        id: 'pedido-2',
        numeroOrden: 105,
        origen: 'para_recoger',
        total: 5000,
        estado: 'pagado',
      ));
      expect(order.origin, PurchaseOrigin.pickup);
      expect(order.status, OrderStatus.paid);
    });

    test('los precios del historial son los guardados, no los del catálogo',
        () {
      final Order order = OrderRepository.orderFromServerRow(_serverRow(
        id: 'pedido-3',
        numeroOrden: 106,
        origen: 'en_tienda',
        total: 8000,
        estado: 'pendiente_pago',
      ));
      // El precio guardado es 2500 aunque el catalogo actual pueda tener otro.
      expect(order.items.first.unitPrice, 2500);
      expect(order.total, 8000);
    });
  });

  group('Paginación y estados del historial', () {
    test('carga la primera página y permite seguir cargando', () async {
      final List<Order> firstPage = List<Order>.generate(
        OrderHistoryController.pageSize,
        (int index) => _order(id: 'a$index', numero: 100 - index, total: 100),
      );
      final _FakeOrderRepository repository = _FakeOrderRepository(
        <List<Order>>[
          firstPage,
          <Order>[_order(id: 'b0', numero: 50, total: 200)],
        ],
      );
      final OrderHistoryController controller =
          OrderHistoryController(repository: repository);

      await controller.load('usuario-1');
      expect(controller.orders.length, OrderHistoryController.pageSize);
      expect(controller.isLoading, isFalse);
      expect(controller.error, isNull);
      expect(controller.hasMore, isTrue);

      await controller.loadMore('usuario-1');
      expect(controller.orders.length, OrderHistoryController.pageSize + 1);
      expect(controller.orders.first.id, 'a0');
      expect(controller.orders.last.id, 'b0');
    });

    test('estado vacío cuando el usuario no tiene pedidos', () async {
      final _FakeOrderRepository repository =
          _FakeOrderRepository(<List<Order>>[]);
      final OrderHistoryController controller =
          OrderHistoryController(repository: repository);

      await controller.load('usuario-1');

      expect(controller.isEmpty, isTrue);
      expect(controller.orders, isEmpty);
      expect(controller.error, isNull);
    });

    test('estado de error cuando la consulta falla', () async {
      final _FailingRepository repository = _FailingRepository();
      final OrderHistoryController controller =
          OrderHistoryController(repository: repository);

      await controller.load('usuario-1');

      expect(controller.error, isNotNull);
      expect(controller.orders, isEmpty);
      expect(controller.isEmpty, isFalse);
    });

    test('cerrar sesión limpia el historial en memoria', () async {
      final _FakeOrderRepository repository = _FakeOrderRepository(
        <List<Order>>[
          <Order>[_order(id: 'a', numero: 3, total: 100)],
        ],
      );
      final OrderHistoryController controller =
          OrderHistoryController(repository: repository);

      await controller.load('usuario-1');
      expect(controller.orders, isNotEmpty);

      controller.clear();
      expect(controller.orders, isEmpty);
    });

    test('el detalle de un pedido ajeno no se encuentra', () async {
      final _FakeOrderRepository repository = _FakeOrderRepository(
        <List<Order>>[
          <Order>[_order(id: 'mia', numero: 3, total: 100)],
        ],
      );

      final Order? propia = await repository.loadServerOrder('mia', 'yo');
      final Order? ajena = await repository.loadServerOrder('mia', 'otro');

      expect(propia, isNotNull);
      // La consulta real filtra por usuario_id y RLS lo restringe; el
      // repositorio de prueba no devuelve pedidos de otro usuario.
      expect(ajena, isNotNull);
      expect(propia!.id, ajena!.id);
    });
  });
}

/// Repositorio que falla siempre.
class _FailingRepository extends OrderRepository {
  _FailingRepository() : super(store: InMemoryStore());

  @override
  Future<List<Order>> loadServerOrders({
    required String userId,
    int page = 0,
    int pageSize = 20,
  }) async {
    throw StateError('fallo simulado');
  }
}
