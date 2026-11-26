import 'package:flutter_test/flutter_test.dart';
import 'package:mercamigo_app/data/local/key_value_store.dart';
import 'package:mercamigo_app/data/models/purchase_origin.dart';
import 'package:mercamigo_app/repositories/cart_repository.dart';
import 'package:mercamigo_app/state/origin_controller.dart';

OriginController buildOrigin(InMemoryStore store) =>
    OriginController(cartRepository: CartRepository(store));

void main() {
  group('Conservación del origen de compra', () {
    test('guarda el origen "En tienda"', () async {
      final InMemoryStore store = InMemoryStore();
      final OriginController controller = buildOrigin(store);

      await controller.setOrigin(PurchaseOrigin.inStore);

      expect(controller.origin, PurchaseOrigin.inStore);
      expect(controller.hasOrigin, isTrue);
    });

    test('guarda el origen "Pedido para recoger"', () async {
      final InMemoryStore store = InMemoryStore();
      final OriginController controller = buildOrigin(store);

      await controller.setOrigin(PurchaseOrigin.pickup);

      expect(controller.origin, PurchaseOrigin.pickup);
    });

    test('el origen se conserva al reiniciar la app', () async {
      final InMemoryStore store = InMemoryStore();
      final OriginController first = buildOrigin(store);
      await first.setOrigin(PurchaseOrigin.pickup);

      final OriginController second = buildOrigin(store);
      await second.load();

      expect(second.origin, PurchaseOrigin.pickup);
    });

    test('no se cambia automáticamente por ubicación (no hay GPS)', () async {
      final InMemoryStore store = InMemoryStore();
      final OriginController controller = buildOrigin(store);
      await controller.setOrigin(PurchaseOrigin.inStore);

      // Simula varias interacciones con la app; el origen no debe cambiar.
      await controller.load();
      await controller.setOrigin(PurchaseOrigin.inStore);

      expect(controller.origin, PurchaseOrigin.inStore);
    });

    test('el origen se guarda con el valor válido de pedidos.origen', () async {
      final InMemoryStore store = InMemoryStore();
      final OriginController controller = buildOrigin(store);

      await controller.setOrigin(PurchaseOrigin.pickup);

      expect(
        await store.readString('mercamigo.cart.origin'),
        PurchaseOrigin.pickup.serverValue,
      );
      expect(PurchaseOrigin.pickup.serverValue, 'para_recoger');
      expect(PurchaseOrigin.inStore.serverValue, 'en_tienda');
    });

    test('las etiquetas del origen son las del prototipo', () {
      expect(PurchaseOrigin.inStore.label, 'En tienda');
      expect(PurchaseOrigin.pickup.label, 'Pedido para recoger');
      expect(PurchaseOrigin.inStore.summaryLabel, 'Origen: En tienda');
      expect(PurchaseOrigin.pickup.summaryLabel, 'Origen: Pedido para recoger');
    });
  });
}
