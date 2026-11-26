import 'dart:convert';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/app_date_time.dart';
import '../core/utils/order_number.dart';
import '../data/local/key_value_store.dart';
import '../data/models/cart_item.dart';
import '../data/models/order.dart';
import '../data/models/purchase_origin.dart';

/// Puerta de salida hacia el servidor para crear pedidos.
///
/// La implementa [SupabaseOrderGateway] (RPC `crear_pedido`). Si la app
/// corre sin servidor, no hay gateway y las órdenes se guardan solo en el
/// dispositivo.
abstract interface class OrderGateway {
  /// `true` cuando el gateway puede crear pedidos ahora mismo.
  bool get isAvailable;

  /// Crea el pedido en el servidor y devuelve la orden con su número.
  Future<Order> createOrder({
    required List<CartItem> items,
    required PurchaseOrigin origin,
    required String idempotencyKey,
    required String storeId,
  });
}

/// Resultado de cancelar un pedido.
class CancelOrderResult {
  const CancelOrderResult({
    required this.status,
    required this.message,
    required this.cancelled,
  });

  /// Estado real que quedó en el servidor.
  final OrderStatus status;

  /// Mensaje del servidor para mostrar al comprador.
  final String message;

  /// `true` solo si esta llamada canceló el pedido.
  final bool cancelled;
}

/// Gateway contra la función `public.crear_pedido`.
class SupabaseOrderGateway implements OrderGateway {
  const SupabaseOrderGateway(this._client);

  final SupabaseClient _client;

  @override
  bool get isAvailable => _client.auth.currentSession != null;

  @override
  Future<Order> createOrder({
    required List<CartItem> items,
    required PurchaseOrigin origin,
    required String idempotencyKey,
    required String storeId,
  }) async {
    final Object? response = await _client.rpc(
      'crear_pedido',
      params: <String, dynamic>{
        'p_tienda_id': storeId,
        'p_origen': origin.serverValue,
        'p_items': items
            .map(
              (CartItem item) => <String, dynamic>{
                'producto_id': item.productId,
                'cantidad': item.quantity,
              },
            )
            .toList(growable: false),
        'p_clave_idempotencia': idempotencyKey,
      },
    );

    return _parseOrder(response);
  }

  Order _parseOrder(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Respuesta inesperada de crear_pedido');
    }
    final Map<String, dynamic> map = Map<String, dynamic>.from(raw);

    final List<OrderItem> items =
        (map['items'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(
              (Map<String, dynamic> row) => OrderItem(
                productId: row['producto_id'] as String? ?? '',
                name: row['nombre_producto'] as String? ?? '',
                quantity: (row['cantidad'] as num?)?.toInt() ?? 0,
                unitPrice: (row['precio_unitario_cop'] as num?)?.toInt() ?? 0,
                subtotal: (row['subtotal_cop'] as num?)?.toInt(),
              ),
            )
            .toList(growable: false);

    final int numeroOrden = (map['numero_orden'] as num?)?.toInt() ?? 0;

    return Order(
      id: map['pedido_id'] as String? ?? '',
      orderNumber: formatOrderNumber(numeroOrden),
      numeroOrden: numeroOrden,
      createdAt:
          parseServerDate(map['creado_en'] as String?) ??
          DateTime.now().toUtc(),
      origin: PurchaseOrigin.fromServer(map['origen'] as String?),
      items: items,
      subtotal: items.fold<int>(
        0,
        (int sum, OrderItem item) => sum + (item.subtotal ?? 0),
      ),
      discount: 0,
      total: (map['total_cop'] as num?)?.toInt() ?? 0,
      status: OrderStatus.fromServer(map['estado'] as String?),
      idempotencyKey: map['pedido_id'] as String?,
      // El plazo lo fija el servidor: la app solo lo cuenta.
      expiresAt: parseServerDate(map['expira_en'] as String?),
      isServerOrder: true,
    );
  }
}

/// Persistencia y creación de pedidos.
///
/// Cuando hay gateway disponible el pedido se crea **en el servidor** (el
/// total lo recalcula el servidor y la base asigna el `numero_orden`). Sin
/// gateway, el pedido se guarda solo en el dispositivo.
class OrderRepository {
  OrderRepository({
    required this.store,
    this.gateway,
    this.client,
    Random? random,
  }) : random = random ?? Random();

  static const String _ordersKey = 'mercamigo.orders';
  static const String _sequenceKey = 'mercamigo.orders.sequence';

  final KeyValueStore store;
  final OrderGateway? gateway;

  /// Cliente de Supabase para leer el historial de pedidos del usuario.
  final SupabaseClient? client;

  final Random random;

  List<Order> _orders = <Order>[];

  /// `true` cuando las órdenes se crean en el servidor.
  bool get usesServer => gateway?.isAvailable ?? false;

  /// �"rdenes guardadas localmente (del más reciente al más antiguo).
  List<Order> get orders => List<Order>.unmodifiable(_orders);

  /// Carga las órdenes guardadas en el dispositivo.
  Future<void> load() async {
    final String? raw = await store.readString(_ordersKey);
    if (raw == null || raw.isEmpty) {
      _orders = <Order>[];
      return;
    }
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) {
        _orders = <Order>[];
        return;
      }
      final List<Order> orders = decoded
          .whereType<Map<String, dynamic>>()
          .map(Order.fromJson)
          .toList();
      orders.sort((Order a, Order b) => b.createdAt.compareTo(a.createdAt));
      _orders = orders;
    } on FormatException {
      _orders = <Order>[];
    }
  }

  /// Crea el pedido.
  ///
  /// Con servidor disponible delega en [OrderGateway.createOrder]; si el
  /// servidor rechaza la orden, el error se propaga para que el carrito
  /// **no** se borre.
  Future<Order> createOrder({
    required List<CartItem> items,
    required PurchaseOrigin origin,
    required String idempotencyKey,
    String? storeId,
    DateTime? createdAt,
  }) async {
    if (items.isEmpty) {
      throw StateError('No se puede crear una orden sin productos.');
    }

    final Order order;
    final OrderGateway? activeGateway = gateway;
    if (activeGateway != null && activeGateway.isAvailable) {
      if (storeId == null || storeId.isEmpty) {
        throw StateError(
          'La tienda no está configurada en el servidor. '
          'Un administrador debe registrar la tienda antes de crear pedidos.',
        );
      }
      order = await activeGateway.createOrder(
        items: items,
        origin: origin,
        idempotencyKey: idempotencyKey,
        storeId: storeId,
      );
    } else {
      order = await _createLocalOrder(
        items: items,
        origin: origin,
        idempotencyKey: idempotencyKey,
        createdAt: createdAt,
      );
    }

    _orders = <Order>[order, ..._orders];
    await _persist();
    return order;
  }

  /// Cancela un pedido **pendiente de pago** del usuario.
  ///
  /// La decisión la toma el servidor (`cancelar_pedido`), que comprueba la
  /// propiedad del pedido, la caducidad y que no exista un pago. Un pedido
  /// pagado no se cancela desde la app: no hay reembolso electrónico.
  Future<CancelOrderResult> cancelOrder(Order order) async {
    final SupabaseClient? supabase = client;
    if (supabase == null) {
      throw StateError('El servidor no está configurado.');
    }

    final Object? response = await supabase.rpc(
      'cancelar_pedido',
      params: <String, dynamic>{'p_pedido_id': order.id},
    );
    if (response is! Map) {
      throw const FormatException('Respuesta inesperada de cancelar_pedido');
    }
    final Map<String, dynamic> map = Map<String, dynamic>.from(response);
    final OrderStatus status = OrderStatus.fromServer(map['estado'] as String?);
    final String message =
        map['mensaje'] as String? ?? 'El pedido cambió de estado.';

    if (status != order.status) {
      _orders = _orders
          .map(
            (Order item) => item.id == order.id
                ? item.copyWith(
                    status: status,
                    clearExpiresAt: status != OrderStatus.pendingPayment,
                  )
                : item,
          )
          .toList();
      await _persist();
    }

    return CancelOrderResult(
      status: status,
      message: message,
      cancelled: status == OrderStatus.cancelled,
    );
  }

  /// Carga el historial de pedidos del usuario autenticado.
  ///
  /// La política `pedidos_propios` ya limita la consulta a los pedidos del
  /// usuario de la sesion; el filtro por `usuario_id` es solo defensivo.
  /// Los precios y subtotales son los que quedaron guardados en
  /// `detalle_pedido` al confirmar la orden: no se recalculan con el
  /// catalogo actual.
  Future<List<Order>> loadServerOrders({
    required String userId,
    int page = 0,
    int pageSize = 20,
  }) async {
    final SupabaseClient? supabase = client;
    if (supabase == null) return <Order>[];

    final int from = page * pageSize;
    final int to = from + pageSize - 1;

    final List<Map<String, dynamic>> rows =
        (await supabase
                .from('pedidos')
                .select(
                  'id, numero_orden, tienda_id, origen, total_cop, estado, '
                  'creado_en, expira_en, tiendas(nombre), '
                  'detalle_pedido(producto_id, nombre_producto, cantidad, '
                  'precio_unitario_cop, subtotal_cop)',
                )
                .eq('usuario_id', userId)
                .order('numero_orden', ascending: false)
                .range(from, to))
            .cast<Map<String, dynamic>>();

    return rows.map(orderFromServerRow).toList(growable: false);
  }

  /// Carga el detalle de un pedido del usuario autenticado.
  Future<Order?> loadServerOrder(String orderId, String userId) async {
    final SupabaseClient? supabase = client;
    if (supabase == null) return null;
    try {
      final List<Map<String, dynamic>> rows =
          (await supabase
                  .from('pedidos')
                  .select(
                    'id, numero_orden, tienda_id, origen, total_cop, estado, '
                    'creado_en, expira_en, tiendas(nombre), '
                    'detalle_pedido(producto_id, nombre_producto, cantidad, '
                    'precio_unitario_cop, subtotal_cop)',
                  )
                  .eq('id', orderId)
                  .eq('usuario_id', userId)
                  .limit(1))
              .cast<Map<String, dynamic>>();
      if (rows.isEmpty) return null;
      return orderFromServerRow(rows.first);
    } catch (_) {
      return null;
    }
  }

  /// Borra la copia local de los pedidos (por ejemplo, al cerrar sesión).
  Future<void> clearLocal() async {
    _orders = <Order>[];
    await store.remove(_ordersKey);
  }

  /// Convierte una fila de `pedidos` (con `detalle_pedido` embebido) en un
  /// [Order].
  ///
  /// Usa los precios y subtotales **guardados** en `detalle_pedido`: el
  /// historial no se recalcula con el catálogo actual.
  static Order orderFromServerRow(Map<String, dynamic> row) {
    final Object? rawDetails = row['detalle_pedido'];
    final List<Map<String, dynamic>> details = rawDetails is List
        ? rawDetails.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

    final List<OrderItem> items = details
        .map(
          (Map<String, dynamic> detail) => OrderItem(
            productId: detail['producto_id'] as String? ?? '',
            name: detail['nombre_producto'] as String? ?? '',
            quantity: (detail['cantidad'] as num?)?.toInt() ?? 0,
            unitPrice: (detail['precio_unitario_cop'] as num?)?.toInt() ?? 0,
            subtotal: (detail['subtotal_cop'] as num?)?.toInt(),
          ),
        )
        .toList(growable: false);

    final int numeroOrden = (row['numero_orden'] as num?)?.toInt() ?? 0;

    return Order(
      id: row['id'] as String? ?? '',
      orderNumber: formatOrderNumber(numeroOrden),
      numeroOrden: numeroOrden,
      createdAt:
          parseServerDate(row['creado_en'] as String?) ??
          DateTime.now().toUtc(),
      origin: PurchaseOrigin.fromServer(row['origen'] as String?),
      items: items,
      subtotal: items.fold<int>(
        0,
        (int sum, OrderItem item) => sum + (item.subtotal ?? 0),
      ),
      discount: 0,
      total: (row['total_cop'] as num?)?.toInt() ?? 0,
      status: OrderStatus.fromServer(row['estado'] as String?),
      storeId: row['tienda_id'] as String?,
      // El plazo lo fija el servidor (pedidos.expira_en).
      expiresAt: parseServerDate(row['expira_en'] as String?),
      isServerOrder: true,
    );
  }

  Future<Order> _createLocalOrder({
    required List<CartItem> items,
    required PurchaseOrigin origin,
    required String idempotencyKey,
    DateTime? createdAt,
  }) async {
    final List<OrderItem> orderItems = items
        .map(
          (CartItem item) => OrderItem(
            productId: item.productId,
            name: item.name,
            quantity: item.quantity,
            unitPrice: item.unitPrice,
            subtotal: item.payableTotal,
            discount: item.discount,
            promotionTitle: item.promotion?.title,
          ),
        )
        .toList(growable: false);

    final int subtotal = orderItems.fold<int>(
      0,
      (int sum, OrderItem item) => sum + item.unitPrice * item.quantity,
    );
    final int discount = orderItems.fold<int>(
      0,
      (int sum, OrderItem item) => sum + item.discount,
    );
    final int total = orderItems.fold<int>(
      0,
      (int sum, OrderItem item) => sum + item.payableTotal,
    );

    final DateTime created = (createdAt ?? DateTime.now()).toUtc();

    return Order(
      id: _generateId(),
      orderNumber: await nextOrderNumber(),
      createdAt: created,
      origin: origin,
      items: orderItems,
      subtotal: subtotal,
      discount: discount,
      total: total,
      status: OrderStatus.pendingPayment,
      idempotencyKey: idempotencyKey,
      // Sin servidor se aplica el mismo plazo de 15 minutos.
      expiresAt: created.add(const Duration(minutes: 15)),
      isServerOrder: false,
    );
  }

  /// Siguiente número de orden visible, sin colisiones con lo guardado.
  Future<String> nextOrderNumber() async {
    int max = 100;
    for (final Order order in _orders) {
      final int? parsed = _parseSequence(order.orderNumber);
      if (parsed != null && parsed > max) max = parsed;
    }
    final String? stored = await store.readString(_sequenceKey);
    final int? storedParsed = _parseSequence(stored ?? '');
    if (storedParsed != null && storedParsed > max) max = storedParsed;
    return formatOrderNumber(max + 1);
  }

  String _generateId() {
    final String randomPart = random
        .nextInt(0xFFFFFF)
        .toRadixString(16)
        .toUpperCase()
        .padLeft(6, '0');
    return 'ORD-$randomPart';
  }

  Future<void> _persist() async {
    await store.writeString(
      _ordersKey,
      jsonEncode(_orders.map((Order order) => order.toJson()).toList()),
    );
    if (_orders.isNotEmpty) {
      await store.writeString(_sequenceKey, _orders.first.orderNumber);
    }
  }

  static int? _parseSequence(String orderNumber) =>
      parseOrderNumber(orderNumber);
}
