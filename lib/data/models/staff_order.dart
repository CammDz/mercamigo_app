import '../../core/utils/app_date_time.dart';
import '../../core/utils/order_number.dart';
import 'order.dart';
import 'purchase_origin.dart';

/// Pedido resumido que ve el personal de caja.
///
/// Solo incluye el **nombre** del cliente, nunca su correo, teléfono ni
/// identificadores de autenticación. Los importes y estados vienen del
/// servidor; la app no los recalcula.
class StaffOrderSummary {
  const StaffOrderSummary({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.origin,
    required this.total,
    required this.createdAt,
    required this.customerName,
    required this.units,
    this.expiresAt,
    this.paidAt,
    this.deliveredAt,
  });

  final String id;
  final String orderNumber;
  final OrderStatus status;
  final PurchaseOrigin origin;
  final int total;
  final DateTime createdAt;
  final String customerName;
  final int units;
  final DateTime? expiresAt;
  final DateTime? paidAt;
  final DateTime? deliveredAt;

  String get qrPayload => id.isNotEmpty ? id : orderNumber;

  bool get isExpiredByClock =>
      status == OrderStatus.pendingPayment &&
      expiresAt != null &&
      DateTime.now().toUtc().isAfter(expiresAt!.toUtc());

  static StaffOrderSummary fromJson(Map<String, dynamic> json) {
    final int number = (json['numero_orden'] as num?)?.toInt() ?? 0;
    return StaffOrderSummary(
      id: json['pedido_id'] as String? ?? '',
      orderNumber: formatOrderNumber(number),
      status: OrderStatus.fromServer(json['estado'] as String?),
      origin: PurchaseOrigin.fromServer(json['origen'] as String?),
      total: (json['total_cop'] as num?)?.toInt() ?? 0,
      createdAt: parseServerDate(json['creado_en'] as String?) ??
          DateTime.now().toUtc(),
      customerName: (json['cliente_nombre'] as String? ?? '').trim(),
      units: (json['unidades'] as num?)?.toInt() ?? 0,
      expiresAt: parseServerDate(json['expira_en'] as String?),
      paidAt: parseServerDate(json['pagado_en'] as String?),
      deliveredAt: parseServerDate(json['entregado_en'] as String?),
    );
  }
}

/// Línea histórica del recibo.
class StaffOrderItem {
  const StaffOrderItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
  });

  final String name;
  final int quantity;
  final int unitPrice;
  final int subtotal;

  static StaffOrderItem fromJson(Map<String, dynamic> json) {
    final int quantity = (json['cantidad'] as num?)?.toInt() ?? 0;
    final int unitPrice = (json['precio_unitario_cop'] as num?)?.toInt() ?? 0;
    return StaffOrderItem(
      name: json['nombre_producto'] as String? ?? '',
      quantity: quantity,
      unitPrice: unitPrice,
      subtotal: (json['subtotal_cop'] as num?)?.toInt() ??
          quantity * unitPrice,
    );
  }
}

/// Recibo completo de un pedido para la caja.
class StaffOrderDetail {
  const StaffOrderDetail({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.origin,
    required this.total,
    required this.createdAt,
    required this.customerName,
    required this.items,
    this.expiresAt,
    this.paidAt,
    this.deliveredAt,
    this.storeName,
    this.storeAddress,
  });

  final String id;
  final String orderNumber;
  final OrderStatus status;
  final PurchaseOrigin origin;
  final int total;
  final DateTime createdAt;
  final String customerName;
  final List<StaffOrderItem> items;
  final DateTime? expiresAt;
  final DateTime? paidAt;
  final DateTime? deliveredAt;
  final String? storeName;
  final String? storeAddress;

  String get qrPayload => id.isNotEmpty ? id : orderNumber;

  int get units =>
      items.fold<int>(0, (int sum, StaffOrderItem item) => sum + item.quantity);

  bool get isExpiredByClock =>
      status == OrderStatus.pendingPayment &&
      expiresAt != null &&
      DateTime.now().toUtc().isAfter(expiresAt!.toUtc());

  StaffOrderDetail copyWith({
    OrderStatus? status,
    DateTime? paidAt,
    DateTime? deliveredAt,
  }) {
    return StaffOrderDetail(
      id: id,
      orderNumber: orderNumber,
      status: status ?? this.status,
      origin: origin,
      total: total,
      createdAt: createdAt,
      customerName: customerName,
      items: items,
      expiresAt: expiresAt,
      paidAt: paidAt ?? this.paidAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      storeName: storeName,
      storeAddress: storeAddress,
    );
  }

  static StaffOrderDetail fromJson(Map<String, dynamic> json) {
    final int number = (json['numero_orden'] as num?)?.toInt() ?? 0;
    final List<dynamic> rawItems =
        json['items'] as List<dynamic>? ?? const <dynamic>[];
    return StaffOrderDetail(
      id: json['pedido_id'] as String? ?? '',
      orderNumber: formatOrderNumber(number),
      status: OrderStatus.fromServer(json['estado'] as String?),
      origin: PurchaseOrigin.fromServer(json['origen'] as String?),
      total: (json['total_cop'] as num?)?.toInt() ?? 0,
      createdAt: parseServerDate(json['creado_en'] as String?) ??
          DateTime.now().toUtc(),
      customerName: (json['cliente_nombre'] as String? ?? '').trim(),
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(StaffOrderItem.fromJson)
          .toList(growable: false),
      expiresAt: parseServerDate(json['expira_en'] as String?),
      paidAt: parseServerDate(json['pagado_en'] as String?),
      deliveredAt: parseServerDate(json['entregado_en'] as String?),
      storeName: json['tienda_nombre'] as String?,
      storeAddress: json['tienda_direccion'] as String?,
    );
  }
}

/// Resultado de buscar un pedido por número o código de barras.
class StaffOrderSearchResult {
  const StaffOrderSearchResult({
    required this.found,
    this.message,
    this.order,
  });

  final bool found;
  final String? message;
  final StaffOrderDetail? order;
}

/// Resultado de una transición de caja (pago o entrega).
class StaffActionOutcome {
  const StaffActionOutcome({
    required this.status,
    required this.message,
    required this.registered,
    required this.alreadyDone,
  });

  final OrderStatus status;
  final String message;
  final bool registered;
  final bool alreadyDone;
}

/// Miembro del personal con su rol.
class StaffMember {
  const StaffMember({
    required this.userId,
    required this.role,
    required this.name,
    required this.email,
  });

  final String userId;
  final String role;
  final String name;
  final String email;

  bool get isAdmin => role == 'administrador';

  static StaffMember fromJson(Map<String, dynamic> json) {
    return StaffMember(
      userId: json['usuario_id'] as String? ?? '',
      role: json['rol'] as String? ?? '',
      name: json['nombre'] as String? ?? '',
      email: json['correo'] as String? ?? '',
    );
  }
}

/// Punto de la serie diaria de ventas.
class SalesReportPoint {
  const SalesReportPoint({
    required this.date,
    required this.orders,
    required this.sales,
  });

  final DateTime date;
  final int orders;
  final int sales;

  static SalesReportPoint fromJson(Map<String, dynamic> json) {
    final DateTime parsed =
        parseCalendarDate(json['fecha'] as String?) ?? DateTime.now();
    return SalesReportPoint(
      date: parsed,
      orders: (json['pedidos'] as num?)?.toInt() ?? 0,
      sales: (json['ventas'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Producto más vendido del periodo.
class TopProduct {
  const TopProduct({
    required this.name,
    required this.units,
    required this.sales,
  });

  final String name;
  final int units;
  final int sales;

  static TopProduct fromJson(Map<String, dynamic> json) {
    return TopProduct(
      name: json['nombre'] as String? ?? '',
      units: (json['unidades'] as num?)?.toInt() ?? 0,
      sales: (json['ventas'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Reporte real de ventas calculado por el servidor en America/Bogota.
///
/// Un pedido se cuenta **una sola vez** por su estado actual (`pagado` o
/// `entregado`); no se suman ambos estados porque son excluyentes.
class SalesReport {
  const SalesReport({
    required this.from,
    required this.to,
    required this.totalSales,
    required this.totalOrders,
    required this.averageTicket,
    required this.points,
    required this.topProducts,
  });

  final DateTime from;
  final DateTime to;
  final int totalSales;
  final int totalOrders;
  final int averageTicket;
  final List<SalesReportPoint> points;
  final List<TopProduct> topProducts;

  static SalesReport fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawPoints =
        json['serie'] as List<dynamic>? ?? const <dynamic>[];
    final List<dynamic> rawProducts =
        json['productos'] as List<dynamic>? ?? const <dynamic>[];
    return SalesReport(
      from: parseCalendarDate(json['desde'] as String?) ?? DateTime.now(),
      to: parseCalendarDate(json['hasta'] as String?) ?? DateTime.now(),
      totalSales: (json['total_ventas'] as num?)?.toInt() ?? 0,
      totalOrders: (json['total_pedidos'] as num?)?.toInt() ?? 0,
      averageTicket: (json['ticket_promedio'] as num?)?.toInt() ?? 0,
      points: rawPoints
          .whereType<Map<String, dynamic>>()
          .map(SalesReportPoint.fromJson)
          .toList(growable: false),
      topProducts: rawProducts
          .whereType<Map<String, dynamic>>()
          .map(TopProduct.fromJson)
          .toList(growable: false),
    );
  }
}
