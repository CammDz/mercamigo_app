import 'package:flutter_test/flutter_test.dart';
import 'package:mercamigo_app/data/models/order.dart';
import 'package:mercamigo_app/data/models/purchase_origin.dart';
import 'package:mercamigo_app/data/models/staff_order.dart';

void main() {
  group('Pedido de caja', () {
    test('el QR usa el identificador del pedido, no el número visible', () {
      final StaffOrderDetail order = StaffOrderDetail.fromJson(
        <String, dynamic>{
          'pedido_id': 'pedido-uuid-1',
          'numero_orden': 123,
          'estado': 'pendiente_pago',
          'origen': 'en_tienda',
          'total_cop': 9600,
          'creado_en': '2026-11-25T15:30:00Z',
          'cliente_nombre': 'Ana Pérez',
          'items': <dynamic>[
            <String, dynamic>{
              'nombre_producto': 'Arroz 500 g',
              'cantidad': 2,
              'precio_unitario_cop': 3200,
              'subtotal_cop': 6400,
            },
            <String, dynamic>{
              'nombre_producto': 'Leche 1 L',
              'cantidad': 1,
              'precio_unitario_cop': 3200,
              'subtotal_cop': 3200,
            },
          ],
        },
      );

      expect(order.orderNumber, 'MCA-000123');
      expect(order.qrPayload, 'pedido-uuid-1');
      expect(order.customerName, 'Ana Pérez');
      expect(order.origin, PurchaseOrigin.inStore);
      expect(order.units, 3);
      expect(order.items.length, 2);
      expect(
        order.items.fold<int>(
          0,
          (int sum, StaffOrderItem item) => sum + item.subtotal,
        ),
        order.total,
      );
    });

    test('una orden cancelada no se puede cobrar en la vista de caja', () {
      final StaffOrderDetail order = StaffOrderDetail.fromJson(
        <String, dynamic>{
          'pedido_id': 'pedido-uuid-2',
          'numero_orden': 124,
          'estado': 'cancelado',
          'origen': 'catalogo',
          'total_cop': 0,
          'creado_en': '2026-11-25T15:30:00Z',
          'cliente_nombre': 'Luis',
          'items': <dynamic>[],
        },
      );

      expect(order.status, OrderStatus.cancelled);
      expect(order.isExpiredByClock, isFalse);
    });

    test('el reporte no inventa cifras cuando viene vacío', () {
      final SalesReport report = SalesReport.fromJson(<String, dynamic>{
        'desde': '2026-11-25',
        'hasta': '2026-11-25',
        'total_ventas': 0,
        'total_pedidos': 0,
        'ticket_promedio': 0,
        'serie': <dynamic>[],
        'productos': <dynamic>[],
      });

      expect(report.totalSales, 0);
      expect(report.totalOrders, 0);
      expect(report.points, isEmpty);
      expect(report.topProducts, isEmpty);
    });

    test('el reporte lee la serie y los productos del servidor', () {
      final SalesReport report = SalesReport.fromJson(<String, dynamic>{
        'desde': '2026-11-24',
        'hasta': '2026-11-25',
        'total_ventas': 48000,
        'total_pedidos': 3,
        'ticket_promedio': 16000,
        'serie': <dynamic>[
          <String, dynamic>{
            'fecha': '2026-11-25',
            'pedidos': 2,
            'ventas': 32000,
          },
        ],
        'productos': <dynamic>[
          <String, dynamic>{
            'nombre': 'Arroz 500 g',
            'unidades': 6,
            'ventas': 19200,
          },
        ],
      });

      expect(report.totalSales, 48000);
      expect(report.totalOrders, 3);
      expect(report.points.single.sales, 32000);
      expect(report.topProducts.single.name, 'Arroz 500 g');
      expect(report.topProducts.single.units, 6);
    });
  });
}
