import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercamigo_app/data/models/order.dart';
import 'package:mercamigo_app/data/models/purchase_origin.dart';
import 'package:mercamigo_app/ui/widgets/order_expiry_countdown.dart';

/// La vigencia de 15 minutos la fija el servidor; la app solo la cuenta.
void main() {
  Order order({
    required DateTime createdAt,
    DateTime? expiresAt,
    OrderStatus status = OrderStatus.pendingPayment,
  }) {
    return Order(
      id: 'pedido-1',
      orderNumber: 'MCA-000104',
      numeroOrden: 104,
      createdAt: createdAt,
      expiresAt: expiresAt,
      origin: PurchaseOrigin.inStore,
      items: const [],
      total: 12000,
      status: status,
      isServerOrder: true,
    );
  }

  group('Vigencia de la orden', () {
    test('Una orden pendiente con plazo a futuro no ha caducado', () {
      final Order o = order(
        createdAt: DateTime.now().toUtc(),
        expiresAt:
            DateTime.now().toUtc().add(const Duration(minutes: 15)),
      );
      expect(o.isExpired, isFalse);
      expect(o.remaining?.inMinutes, 14);
    });

    test('Una orden cuyo plazo ya paso esta expirada', () {
      final Order o = order(
        createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 20)),
        expiresAt:
            DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      );
      expect(o.isExpired, isTrue);
      expect(o.remaining, Duration.zero);
    });

    test('El estado expirado del servidor se respeta', () {
      final Order o = order(
        createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
        expiresAt: null,
        status: OrderStatus.expired,
      );
      expect(o.isExpired, isTrue);
      // Sin plazo no hay cuenta regresiva.
      expect(o.remaining, isNull);
    });

    test('Una orden pagada no caduca aunque tenga plazo', () {
      final Order o = order(
        createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
        expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
        status: OrderStatus.paid,
      );
      expect(o.isExpired, isFalse);
      expect(o.remaining, isNull);
    });
  });

  group('Contador regresivo', () {
    testWidgets('Muestra el tiempo que queda', (WidgetTester tester) async {
      final Order o = order(
        createdAt: DateTime.now().toUtc(),
        expiresAt:
            DateTime.now().toUtc().add(const Duration(minutes: 14, seconds: 59)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: OrderExpiryCountdown(order: o)),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Tu orden vence en'), findsOneWidget);
      expect(find.textContaining('14:5'), findsOneWidget);
    });

    testWidgets('Al llegar a cero avisa y muestra "Orden expirada"',
        (WidgetTester tester) async {
      bool avisado = false;
      final Order o = order(
        createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 16)),
        expiresAt:
            DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrderExpiryCountdown(
              order: o,
              onExpired: () => avisado = true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Orden expirada'), findsOneWidget);
      expect(avisado, isTrue);
    });

    testWidgets('Una orden pagada no muestra contador',
        (WidgetTester tester) async {
      final Order o = order(
        createdAt: DateTime.now().toUtc(),
        expiresAt:
            DateTime.now().toUtc().add(const Duration(minutes: 15)),
        status: OrderStatus.paid,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: OrderExpiryCountdown(order: o)),
        ),
      );
      await tester.pump();

      expect(find.textContaining('vence en'), findsNothing);
      expect(find.text('Orden expirada'), findsNothing);
    });
  });
}
