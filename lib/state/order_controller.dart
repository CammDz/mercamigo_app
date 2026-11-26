import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/models/cart_item.dart';
import '../data/models/order.dart';
import '../data/models/purchase_origin.dart';
import '../repositories/order_repository.dart';
import '../repositories/settings_repository.dart';

/// Estado de los pedidos generados.
///
/// Con servidor configurado la orden se crea en Supabase mediante
/// `public.crear_pedido` (el total lo recalcula el servidor y la base
/// asigna el `numero_orden`). Sin servidor, la orden se guarda solo en el
/// dispositivo y no se puede consultar desde otro.
class OrderController extends ChangeNotifier {
  OrderController({
    required this.orderRepository,
    required this.settingsRepository,
    Uuid? uuid,
  }) : uuid = uuid ?? const Uuid();

  final OrderRepository orderRepository;
  final SettingsRepository settingsRepository;
  final Uuid uuid;

  List<Order> _orders = <Order>[];
  bool _creating = false;
  String? _pendingIdempotencyKey;

  /// Pedidos guardados (del más reciente al más antiguo).
  List<Order> get orders => List<Order>.unmodifiable(_orders);

  /// `true` mientras se está generando un pedido (evita pulsaciones dobles).
  bool get isCreating => _creating;

  /// `true` cuando las órdenes se crean en el servidor.
  bool get usesServer => orderRepository.usesServer;

  /// Restaura los pedidos guardados localmente.
  Future<void> load() async {
    await orderRepository.load();
    _orders = orderRepository.orders;
    notifyListeners();
  }

  /// Genera y guarda un pedido a partir de las líneas del carrito.
  ///
  /// Devuelve `null` si ya hay una generación en curso (doble pulsación) o si
  /// no hay productos. El carrito solo se borra después de que el guardado
  /// termina correctamente.
  Future<Order?> createOrder({
    required List<CartItem> items,
    required PurchaseOrigin origin,
    String? storeId,
    DateTime? createdAt,
  }) async {
    if (_creating) return null;
    if (items.isEmpty) return null;

    _creating = true;
    notifyListeners();
    try {
      // La clave de idempotencia se mantiene entre reintentos: si el usuario
      // pulsa dos veces, el servidor devuelve la misma orden.
      _pendingIdempotencyKey ??= uuid.v4();

      final String? resolvedStoreId = storeId ?? await _activeStoreId();

      final Order order = await orderRepository.createOrder(
        items: items,
        origin: origin,
        idempotencyKey: _pendingIdempotencyKey!,
        storeId: resolvedStoreId,
        createdAt: createdAt,
      );

      _pendingIdempotencyKey = null;
      _orders = orderRepository.orders;
      return order;
    } finally {
      _creating = false;
      notifyListeners();
    }
  }

  /// Cancela un pedido pendiente de pago.
  ///
  /// El servidor decide si se puede cancelar; la app solo refleja el estado
  /// real que devuelve. No se cancela un pedido pagado ni uno caducado.
  Future<CancelOrderResult> cancelOrder(Order order) async {
    final CancelOrderResult result = await orderRepository.cancelOrder(order);
    _orders = orderRepository.orders;
    notifyListeners();
    return result;
  }

  Future<String?> _activeStoreId() async {
    final dynamic location = await settingsRepository.loadActiveServerStore();
    if (location == null) return null;
    return location.id as String?;
  }
}
