import 'package:flutter_test/flutter_test.dart';
import 'package:mercamigo_app/core/utils/app_date_time.dart';
import 'package:mercamigo_app/data/models/order.dart';
import 'package:mercamigo_app/data/models/purchase_origin.dart';

void main() {
  group('Zona horaria de Mercamigo', () {
    test('es America/Bogota con desplazamiento fijo de -05:00', () {
      expect(AppTimeZone.id, 'America/Bogota');
      expect(AppTimeZone.offset, const Duration(hours: -5));
      expect(AppTimeZone.label, 'UTC-05:00');
    });

    test('muestra la hora de Bogota y no la del telefono', () {
      // 18:30 UTC = 13:30 en Bogota.
      final DateTime instant = DateTime.utc(2026, 10, 21, 18, 30);
      expect(formatBogotaDateTime(instant), '21/10/2026 13:30');
      expect(formatBogotaDate(instant), '21/10/2026');
      expect(formatBogotaShortDateTime(instant), '21/10 13:30');
    });

    test('un instante local se muestra igual que el mismo instante en UTC', () {
      final DateTime utc = DateTime.utc(2026, 10, 21, 18, 30);
      final DateTime local = utc.toLocal();
      expect(formatBogotaDateTime(local), formatBogotaDateTime(utc));
    });

    test('la conversion no se aplica dos veces', () {
      final DateTime instant = DateTime.utc(2026, 10, 21, 18, 30);
      // Convertir a Bogota y volver a convertir debe dar lo mismo.
      expect(toBogota(toBogota(instant)), toBogota(instant));
      expect(
        formatBogotaDateTime(toBogota(instant)),
        formatBogotaDateTime(instant),
      );
    });
  });

  group('Lectura de fechas del servidor', () {
    test('interpreta el desplazamiento horario del servidor', () {
      final DateTime parsed = parseServerDate('2026-10-21T13:30:00-05:00')!;
      expect(parsed.toUtc(), DateTime.utc(2026, 10, 21, 18, 30));
      expect(formatBogotaDateTime(parsed), '21/10/2026 13:30');
    });

    test('interpreta la Z de UTC', () {
      final DateTime parsed = parseServerDate('2026-10-21T18:30:00Z')!;
      expect(parsed.toUtc(), DateTime.utc(2026, 10, 21, 18, 30));
      expect(formatBogotaDateTime(parsed), '21/10/2026 13:30');
    });

    test('interpreta el UTC con desplazamiento de PostgREST', () {
      final DateTime parsed = parseServerDate('2026-10-21T18:30:00+00:00')!;
      expect(parsed.toUtc(), DateTime.utc(2026, 10, 21, 18, 30));
    });

    test('ancora a Bogota los valores sin zona horaria', () {
      final DateTime parsed = parseServerDate('2026-10-21 13:30:00')!;
      expect(parsed.toUtc(), DateTime.utc(2026, 10, 21, 18, 30));
      expect(formatBogotaDateTime(parsed), '21/10/2026 13:30');
    });

    test('una fecha sin hora no se confunde con un desplazamiento', () {
      final DateTime parsed = parseServerDate('2026-10-21')!;
      // Medianoche en Bogota.
      expect(parsed.toUtc(), DateTime.utc(2026, 10, 21, 5, 0));
    });

    test('acepta el formato con milisegundos', () {
      final DateTime parsed = parseServerDate('2026-10-21T13:30:00.250-05:00')!;
      expect(parsed.toUtc(), DateTime.utc(2026, 10, 21, 18, 30, 0, 250));
    });

    test('devuelve null con textos vacios o invalidos', () {
      expect(parseServerDate(null), isNull);
      expect(parseServerDate(''), isNull);
      expect(parseServerDate('   '), isNull);
      expect(parseServerDate('no es una fecha'), isNull);
    });
  });

  group('Guardado de fechas', () {
    test('siempre se serializa en UTC', () {
      final DateTime local = DateTime.utc(2026, 10, 21, 18, 30).toLocal();
      final String saved = toServerDate(local);
      expect(saved.endsWith('Z'), isTrue);
      expect(
        parseServerDate(saved)!.toUtc(),
        DateTime.utc(2026, 10, 21, 18, 30),
      );
    });

    test('guardar y leer devuelve el mismo instante', () {
      final DateTime instant = DateTime.utc(2026, 10, 21, 18, 30);
      expect(parseServerDate(toServerDate(instant))!.toUtc(), instant);
    });
  });

  group('Contador de vigencia', () {
    Order buildOrder({
      required DateTime createdAt,
      required DateTime? expiresAt,
      OrderStatus status = OrderStatus.pendingPayment,
    }) {
      return Order(
        id: 'o1',
        orderNumber: 'MCA-000001',
        createdAt: createdAt,
        origin: PurchaseOrigin.inStore,
        items: const <OrderItem>[],
        total: 0,
        status: status,
        expiresAt: expiresAt,
      );
    }

    test('el plazo son 15 minutos de reloj, no de texto', () {
      final DateTime created = DateTime.utc(2026, 10, 21, 18, 30);
      final Order order = buildOrder(
        createdAt: created,
        expiresAt: created.add(const Duration(minutes: 15)),
      );
      expect(order.expiresAtBogota!.hour, 13);
      expect(order.expiresAtBogota!.minute, 45);
      expect(order.expiresAtBogota!.day, 21);
    });

    test('la cuenta regresiva compara instantes', () {
      final DateTime created = DateTime.now().toUtc();
      final Order order = buildOrder(
        createdAt: created,
        expiresAt: created.add(const Duration(minutes: 15)),
      );
      expect(order.isExpired, isFalse);
      final Duration? left = order.remaining;
      expect(left, isNotNull);
      // Quedan unos 15 minutos (con un margen de reloj).
      expect(left!.inMinutes, greaterThanOrEqualTo(14));
      expect(left.inMinutes, lessThanOrEqualTo(15));
    });

    test('convertir la hora no reinicia ni amplia la vigencia', () {
      final DateTime created = DateTime.now().toUtc();
      final Order order = buildOrder(
        createdAt: created,
        expiresAt: created.add(const Duration(minutes: 15)),
      );
      final Duration? antes = order.remaining;
      // Convertir a Bogota no toca el instante.
      order.createdAtBogota;
      order.expiresAtBogota;
      final Duration? despues = order.remaining;
      expect(
        (antes!.inSeconds - despues!.inSeconds).abs(),
        lessThanOrEqualTo(2),
      );
    });

    test('una orden vencida se detecta por su instante', () {
      final DateTime created = DateTime.now().toUtc().subtract(
        const Duration(minutes: 20),
      );
      final Order order = buildOrder(
        createdAt: created,
        expiresAt: created.add(const Duration(minutes: 15)),
      );
      expect(order.isExpired, isTrue);
      expect(order.remaining!.inSeconds, 0);
    });
  });
}
