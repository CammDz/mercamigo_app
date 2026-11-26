import 'package:flutter_test/flutter_test.dart';
import 'package:mercamigo_app/data/local/key_value_store.dart';
import 'package:mercamigo_app/data/models/product.dart';
import 'package:mercamigo_app/repositories/cart_repository.dart';
import 'package:mercamigo_app/repositories/catalog_repository.dart';
import 'package:mercamigo_app/state/cart_controller.dart';

import 'helpers/catalog_fixtures.dart';

CartController buildCart(InMemoryStore store, CatalogRepository catalog) {
  return CartController(
    cartRepository: CartRepository(store),
    catalogRepository: catalog,
  );
}

void main() {
  group('Carrito: sumar y eliminar productos', () {
    test(
      'agregar el mismo producto suma la cantidad en la misma línea',
      () async {
        final CatalogRepository catalog =
            await CatalogFixtures.buildRepository();
        final CartController cart = buildCart(InMemoryStore(), catalog);
        final Product product = catalog.all.first;

        await cart.add(product);
        await cart.add(product);

        expect(cart.items.length, 1);
        expect(cart.items.first.quantity, 2);
        expect(cart.totalUnits, 2);
      },
    );

    test('agregar productos distintos crea una línea por producto', () async {
      final CatalogRepository catalog = await CatalogFixtures.buildRepository();
      final CartController cart = buildCart(InMemoryStore(), catalog);

      await cart.add(catalog.all[0]);
      await cart.add(catalog.all[1]);

      expect(cart.items.length, 2);
      expect(cart.totalUnits, 2);
    });

    test('eliminar un producto quita la línea del carrito', () async {
      final CatalogRepository catalog = await CatalogFixtures.buildRepository();
      final CartController cart = buildCart(InMemoryStore(), catalog);
      final Product product = catalog.all.first;

      await cart.add(product);
      expect(cart.isNotEmpty, isTrue);

      await cart.remove(product.id);

      expect(cart.isEmpty, isTrue);
      expect(cart.items, isEmpty);
      expect(cart.total, 0);
    });

    test('disminuir la cantidad hasta 1 elimina la línea', () async {
      final CatalogRepository catalog = await CatalogFixtures.buildRepository();
      final CartController cart = buildCart(InMemoryStore(), catalog);
      final Product product = catalog.all.first;

      await cart.add(product, quantity: 2);
      await cart.decrease(product.id);
      expect(cart.items.first.quantity, 1);

      await cart.decrease(product.id);
      expect(cart.isEmpty, isTrue);
    });

    test('aumentar la cantidad respeta el stock de demostración', () async {
      final CatalogRepository catalog = await CatalogFixtures.buildRepository();
      final CartController cart = buildCart(InMemoryStore(), catalog);
      final Product product = catalog.all.first;

      await cart.add(product, quantity: product.stock);
      await cart.increase(product.id);

      expect(cart.items.first.quantity, product.stock);
    });
  });

  group('Carrito: totales', () {
    test('subtotal y total se calculan a partir de los datos', () async {
      final CatalogRepository catalog = await CatalogFixtures.buildRepository();
      final CartController cart = buildCart(InMemoryStore(), catalog);
      final Product first = catalog.all[0];
      final Product second = catalog.all[1];

      await cart.add(first, quantity: 3);
      await cart.add(second, quantity: 2);

      expect(cart.subtotal, first.price * 3 + second.price * 2);
      expect(cart.total, cart.subtotal);
      expect(cart.discount, 0);
    });

    test(
      'el total nunca es un valor fijo: sigue al precio del producto',
      () async {
        final CatalogRepository catalog =
            await CatalogFixtures.buildRepository();
        final CartController cart = buildCart(InMemoryStore(), catalog);
        final Product product = catalog.all[2];

        await cart.add(product, quantity: 4);

        expect(cart.total, product.price * 4);
        expect(cart.total, isNot(25000));
      },
    );

    test('el carrito vacío tiene total 0', () async {
      final CatalogRepository catalog = await CatalogFixtures.buildRepository();
      final CartController cart = buildCart(InMemoryStore(), catalog);
      expect(cart.isEmpty, isTrue);
      expect(cart.total, 0);
      expect(cart.subtotal, 0);
      expect(cart.discount, 0);
      expect(cart.totalUnits, 0);
    });
  });

  group('Carrito: persistencia local', () {
    test('el carrito se conserva al reiniciar la app', () async {
      final InMemoryStore store = InMemoryStore();
      final CatalogRepository catalog = await CatalogFixtures.buildRepository();
      final Product product = catalog.all.first;

      final CartController first = buildCart(store, catalog);
      await first.add(product, quantity: 2);

      final CartController second = buildCart(store, catalog);
      await second.load();

      expect(second.items.length, 1);
      expect(second.items.first.productId, product.id);
      expect(second.items.first.quantity, 2);
    });
  });
}
