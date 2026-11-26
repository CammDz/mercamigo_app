import 'package:flutter_test/flutter_test.dart';
import 'package:mercamigo_app/core/utils/order_number.dart';
import 'package:mercamigo_app/data/local/key_value_store.dart';
import 'package:mercamigo_app/repositories/scan_history_repository.dart';

void main() {
  group('Número visible de la orden', () {
    test('Usa el formato MCA con 6 dígitos', () {
      expect(formatOrderNumber(104), 'MCA-000104');
      expect(formatOrderNumber(1), 'MCA-000001');
      expect(formatOrderNumber(999999), 'MCA-999999');
    });

    test('No trunca los números mayores', () {
      expect(formatOrderNumber(1000000), 'MCA-1000000');
      expect(formatOrderNumber(12345678), 'MCA-12345678');
    });

    test('El número no lleva el prefijo duplicado', () {
      // La pantalla muestra el número tal cual: no se le añade otro '#'.
      expect(formatOrderNumber(104).contains('#'), isFalse);
      expect(formatOrderNumber(104).startsWith('MCA-'), isTrue);
    });

    test('Se puede recuperar el consecutivo del número visible', () {
      expect(parseOrderNumber('MCA-000104'), 104);
      expect(parseOrderNumber('MCA-1000000'), 1000000);
      expect(parseOrderNumber('sin formato'), isNull);
      expect(parseOrderNumber('MCA-'), isNull);
    });
  });

  group('Historial de escaneos', () {
    late ScanHistoryRepository repository;

    setUp(() {
      repository = ScanHistoryRepository(store: InMemoryStore());
    });

    ScanHistoryEntry entry(String productId, String code) => ScanHistoryEntry(
      productId: productId,
      productName: 'Producto $productId',
      code: code,
      scannedAt: DateTime.now(),
    );

    test('Guarda y devuelve los escaneos del usuario', () async {
      await repository.add('a@ejemplo.com', entry('p1', '770001'));
      await repository.add('a@ejemplo.com', entry('p2', '770002'));

      final List<ScanHistoryEntry> entries = await repository.load(
        'a@ejemplo.com',
      );

      expect(entries, hasLength(2));
      expect(entries.first.code, '770002');
    });

    test('No guarda un evento por cada deteccion del mismo codigo', () async {
      await repository.add('a@ejemplo.com', entry('p1', '770001'));
      await repository.add('a@ejemplo.com', entry('p1', '770001'));
      await repository.add('a@ejemplo.com', entry('p1', '770001'));

      final List<ScanHistoryEntry> entries = await repository.load(
        'a@ejemplo.com',
      );

      expect(entries, hasLength(1));
    });

    test('Los escaneos de una cuenta no se ven en otra', () async {
      await repository.add('a@ejemplo.com', entry('p1', '770001'));

      expect(await repository.load('b@ejemplo.com'), isEmpty);
    });

    test('Se puede borrar el historial de una cuenta', () async {
      await repository.add('a@ejemplo.com', entry('p1', '770001'));
      await repository.clear('a@ejemplo.com');

      expect(await repository.load('a@ejemplo.com'), isEmpty);
    });
  });
}
