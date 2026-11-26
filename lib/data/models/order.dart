import '../../core/utils/app_date_time.dart';
import 'purchase_origin.dart';

/// Estado del pedido.
///
/// Refleja el `CHECK` de `pedidos.estado`. El pago se hace en caja, así que
/// el estado normal de una orden recién creada es `pendiente_pago`.
enum OrderStatus {
  pendingPayment('pendiente_pago', 'Pendiente de pago'),
  paid('pagado', 'Pagado'),
  delivered('entregado', 'Entregado'),
  cancelled('cancelado', 'Cancelado'),
  expired('expirado', 'Expirado');

  const OrderStatus(this.serverValue, this.label);

  /// Valor válido en `pedidos.estado`.
  final String serverValue;

  final String label;

  static OrderStatus fromServer(String? value) {
    return OrderStatus.values.firstWhere(
      (OrderStatus status) => status.serverValue == value,
      orElse: () => OrderStatus.pendingPayment,
    );
  }
}

/// Copia inmutable de un producto dentro del pedido.
///
/// Refleja `public.detalle_pedido`: `nombre_producto` y
/// `precio_unitario_cop` son la copia de los datos al confirmar la orden,
/// para conservar el historial aunque el catálogo cambie.
class OrderItem {
  const OrderItem({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    this.subtotal,
    this.discount = 0,
    this.promotionTitle,
  });

  /// `detalle_pedido.producto_id` (uuid).
  final String productId;

  /// `detalle_pedido.nombre_producto`.
  final String name;

  /// `detalle_pedido.cantidad`.
  final int quantity;

  /// `detalle_pedido.precio_unitario_cop`.
  final int unitPrice;

  /// `detalle_pedido.subtotal_cop` (columna generada en la base).
  final int? subtotal;

  /// Ahorro aplicado por una promoción (solo en modo demostración local).
  final int discount;

  /// Texto de la promoción aplicada, si hubo.
  final String? promotionTitle;

  /// Subtotal cobrado de esta línea.
  int get payableTotal => subtotal ?? (unitPrice * quantity) - discount;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'productId': productId,
    'name': name,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'subtotal': subtotal,
    'discount': discount,
    'promotionTitle': promotionTitle,
  };

  static OrderItem fromJson(Map<String, dynamic> json) {
    return OrderItem(
      productId: json['productId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      unitPrice: (json['unitPrice'] as num?)?.toInt() ?? 0,
      subtotal: (json['subtotal'] as num?)?.toInt(),
      discount: (json['discount'] as num?)?.toInt() ?? 0,
      promotionTitle: json['promotionTitle'] as String?,
    );
  }
}

/// Pedido generado por la app.
///
/// Cuando la orden se crea en el servidor, [id] es `pedidos.id` (uuid) y
/// [numeroOrden] es `pedidos.numero_orden` (bigint generado por la base).
/// El código QR de la orden representa ese identificador del servidor; el
/// personal de caja lo escanea o escribe el número visible y el servidor
/// comprueba el rol. Ni el QR ni el número autorizan nada por sí solos.
class Order {
  const Order({
    required this.id,
    required this.orderNumber,
    required this.createdAt,
    required this.origin,
    required this.items,
    required this.total,
    required this.status,
    this.numeroOrden,
    this.subtotal = 0,
    this.discount = 0,
    this.idempotencyKey,
    this.storeId,
    this.expiresAt,
    this.isServerOrder = false,
  });

  /// Identificador interno. En el servidor es `pedidos.id` (uuid).
  final String id;

  /// Número visible de la orden (texto con el formato de la interfaz).
  final String orderNumber;

  /// `pedidos.numero_orden` (null en las ordenes locales).
  final int? numeroOrden;

  final DateTime createdAt;
  final PurchaseOrigin origin;
  final List<OrderItem> items;

  /// Subtotal sin descuentos.
  final int subtotal;

  /// Total de descuentos aplicados.
  final int discount;

  /// `pedidos.total_cop`.
  final int total;

  final OrderStatus status;

  /// Fecha de expiración de la orden pendiente de pago.
  ///
  /// La fija el **servidor** (`pedidos.expira_en` = `creado_en` + 15
  /// minutos). Es `null` en las ordenes ya pagadas, entregadas o
  /// canceladas (no caducan) y en las ordenes locales.
  final DateTime? expiresAt;

  /// `true` si la orden pendiente de pago ya supero su plazo.
  ///
  /// Se calcula con el reloj del **servidor**: la app nunca inventa el
  /// plazo, solo lo cuenta. La comparacion es entre **instantes** (UTC),
  /// nunca entre textos de fecha ya formateados, y la conversion a la hora
  /// de Bogota no altera el plazo en ningun momento.
  bool get isExpired {
    if (status != OrderStatus.pendingPayment) {
      return status == OrderStatus.expired;
    }
    final DateTime? deadline = expiresAt;
    if (deadline == null) return false;
    return DateTime.now().toUtc().isAfter(deadline.toUtc());
  }

  /// Tiempo que queda para que caduque la orden (null si no caduca).
  ///
  /// Los dos extremos son instantes: convertir la hora a Bogota para
  /// mostrarla no cambia lo que falta.
  Duration? get remaining {
    final DateTime? deadline = expiresAt;
    if (deadline == null) return null;
    if (status != OrderStatus.pendingPayment) return null;
    final Duration left = deadline.toUtc().difference(DateTime.now().toUtc());
    return left.isNegative ? Duration.zero : left;
  }

  /// Fecha de creacion en hora de Bogota (solo para mostrar).
  DateTime get createdAtBogota => toBogota(createdAt);

  /// Fecha de expiracion en hora de Bogota (solo para mostrar).
  DateTime? get expiresAtBogota =>
      expiresAt == null ? null : toBogota(expiresAt!);

  /// `pedidos.clave_idempotencia`.
  final String? idempotencyKey;

  /// `pedidos.tienda_id`.
  final String? storeId;

  /// `true` cuando la orden vive en el servidor.
  final bool isServerOrder;

  int get totalUnits =>
      items.fold<int>(0, (int sum, OrderItem item) => sum + item.quantity);

  /// Contenido del código QR de la orden.
  ///
  /// Es el identificador del pedido en el servidor (`pedidos.id`), que
  /// `buscar_pedido_personal` acepta igual que el número visible. En las
  /// órdenes locales se usa el número visible. No incluye tokens ni datos
  /// secretos: el servidor autoriza al personal de caja por su rol.
  String get qrPayload => isServerOrder && id.isNotEmpty ? id : orderNumber;

  /// Copia con otro estado (por ejemplo, después de cancelar).
  Order copyWith({
    OrderStatus? status,
    DateTime? expiresAt,
    bool clearExpiresAt = false,
  }) {
    return Order(
      id: id,
      orderNumber: orderNumber,
      numeroOrden: numeroOrden,
      createdAt: createdAt,
      origin: origin,
      items: items,
      subtotal: subtotal,
      discount: discount,
      total: total,
      status: status ?? this.status,
      idempotencyKey: idempotencyKey,
      storeId: storeId,
      expiresAt: clearExpiresAt ? null : (expiresAt ?? this.expiresAt),
      isServerOrder: isServerOrder,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'orderNumber': orderNumber,
    'numeroOrden': numeroOrden,
    'createdAt': toServerDate(createdAt),
    'origin': origin.serverValue,
    'items': items.map((OrderItem item) => item.toJson()).toList(),
    'subtotal': subtotal,
    'discount': discount,
    'total': total,
    'status': status.serverValue,
    'idempotencyKey': idempotencyKey,
    'storeId': storeId,
    'expiresAt': expiresAt == null ? null : toServerDate(expiresAt!),
    'isServerOrder': isServerOrder,
  };

  static Order fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawItems =
        json['items'] as List<dynamic>? ?? const <dynamic>[];
    return Order(
      id: json['id'] as String? ?? '',
      orderNumber: json['orderNumber'] as String? ?? '',
      numeroOrden: (json['numeroOrden'] as num?)?.toInt(),
      createdAt:
          parseServerDate(json['createdAt'] as String?) ??
          DateTime.now().toUtc(),
      origin: PurchaseOrigin.fromServer(json['origin'] as String?),
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(OrderItem.fromJson)
          .toList(),
      subtotal: (json['subtotal'] as num?)?.toInt() ?? 0,
      discount: (json['discount'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      status: OrderStatus.fromServer(json['status'] as String?),
      idempotencyKey: json['idempotencyKey'] as String?,
      storeId: json['storeId'] as String?,
      expiresAt: parseServerDate(json['expiresAt'] as String?),
      isServerOrder: json['isServerOrder'] as bool? ?? false,
    );
  }
}
