import 'package:flutter_test/flutter_test.dart';
import 'package:mercamigo_app/data/models/product.dart';
import 'package:mercamigo_app/data/models/product_category.dart';
import 'package:mercamigo_app/repositories/catalog_repository.dart';

import 'helpers/catalog_fixtures.dart';

void main() {
  group('Búsqueda global del catálogo', () {
    late CatalogRepository repository;

    setUp(() async {
      repository = await CatalogFixtures.buildRepository();
    });

    test('encuentra productos ignorando mayúsculas', () {
      final List<Product> results = repository.search('astra');
      expect(results, isNotEmpty);
      expect(results.first.name.toLowerCase(), contains('astra'));
    });

    test('encuentra productos ignorando tildes', () {
      final List<Product> withTilde = repository.search('lácteos');
      final List<Product> withoutTilde = repository.search('lacteos');

      expect(withTilde, isNotEmpty);
      expect(withoutTilde, isNotEmpty);
      expect(
        withTilde.map((Product p) => p.id),
        equals(withoutTilde.map((Product p) => p.id)),
      );
    });

    test('busca por categoría', () {
      final List<Product> results = repository.search('mascotas');
      expect(results, isNotEmpty);
      for (final Product product in results) {
        expect(product.category.name, 'Mascotas');
      }
    });

    test('la búsqueda global no está limitada a la categoría abierta', () {
      final ProductCategory bebidas =
          repository.activeCategories.firstWhere(
        (ProductCategory category) => category.name == 'Bebidas',
      );

      // Buscando con el filtro de categoría no encuentra el producto de mascotas.
      final List<Product> filtered =
          repository.searchInCategory('perro', bebidas);
      expect(filtered, isEmpty);

      // La misma búsqueda global sí lo encuentra.
      final List<Product> global = repository.search('perro');
      expect(global, isNotEmpty);
      expect(
        global.any((Product p) => p.category.name == 'Mascotas'),
        isTrue,
      );
    });

    test('devuelve vacío cuando no hay coincidencias', () {
      expect(repository.search('zzzz-no-existe'), isEmpty);
      expect(repository.search(''), isEmpty);
      expect(repository.search('   '), isEmpty);
    });

    test('busca también por descripción', () {
      final List<Product> results = repository.search('demostración');
      expect(results, isNotEmpty);
    });

    test('el catálogo tiene al menos 5 productos por categoría', () {
      for (final ProductCategory category in repository.activeCategories) {
        expect(
          repository.byCategory(category).length,
          greaterThanOrEqualTo(5),
          reason: 'La categoría ${category.name} necesita al menos 5 productos',
        );
      }
    });

    test('cada producto tiene id, precio entero, código y stock', () {
      for (final Product product in repository.all) {
        expect(product.id, isNotEmpty);
        expect(product.name, isNotEmpty);
        expect(product.description, isNotEmpty);
        expect(product.price, greaterThan(0));
        expect(product.price, isA<int>());
        expect(product.codes, isNotEmpty);
        expect(product.stock, greaterThan(0));
        expect(product.isDemo, isTrue);
      }
    });

    test('los códigos registrados no se repiten entre productos', () {
      final Set<String> codes = <String>{};
      for (final Product product in repository.all) {
        for (final String code in product.registeredCodes) {
          expect(codes.contains(code), isFalse,
              reason: 'El código $code está repetido');
          codes.add(code);
        }
      }
    });
  });

  group('Búsqueda por código (escáner)', () {
    late CatalogRepository repository;

    setUp(() async {
      repository = await CatalogFixtures.buildRepository();
    });

    test('encuentra el producto por su código registrado', () {
      final Product product = repository.all.first;
      expect(repository.findByCode(product.codes.first.code)?.id, product.id);
    });

    test('encuentra el producto ignorando mayúsculas y espacios', () {
      final Product product = repository.all.first;
      expect(
        repository.findByCode('  ${product.codes.first.code.toUpperCase()} ')?.id,
        product.id,
      );
    });

    test('no encuentra un código desconocido', () {
      expect(repository.findByCode('9999999999999'), isNull);
      expect(repository.findByCode('https://example.com/producto'), isNull);
      expect(repository.findByCode(''), isNull);
    });

    test('el formato de código del proyecto es MERCA-DEMO-{PREFIJO}-{NNN}', () {
      final RegExp pattern = RegExp(r'^MERCA-DEMO-[A-Z]{3}-\d{3}$');
      for (final Product product in repository.all) {
        expect(pattern.hasMatch(product.codes.first.code), isTrue,
            reason: 'Código con formato inesperado: ${product.codes.first.code}');
      }
    });
  });
}
