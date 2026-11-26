import 'dart:convert';

import 'package:mercamigo_app/data/local/key_value_store.dart';
import 'package:mercamigo_app/data/models/product.dart';
import 'package:mercamigo_app/data/models/product_category.dart';
import 'package:mercamigo_app/repositories/catalog_repository.dart';

/// Fixtures del catálogo.
///
/// Reproducen la forma de los datos que devuelve Supabase
/// (`categorias`, `productos`, `codigos_producto`) sin depender del
/// servidor, para que las pruebas sean deterministas.
abstract final class CatalogFixtures {
  /// Categorías del proyecto (mismos nombres que en la base de datos).
  static const List<({String id, String name})> categories =
      <({String id, String name})>[
    (id: 'cat-bebidas', name: 'Bebidas'),
    (id: 'cat-snacks', name: 'Snacks'),
    (id: 'cat-postres', name: 'Postres'),
    (id: 'cat-lacteos', name: 'Lácteos'),
    (id: 'cat-cuidado', name: 'Cuidado personal'),
    (id: 'cat-hogar', name: 'Hogar'),
    (id: 'cat-mascotas', name: 'Mascotas'),
    (id: 'cat-despensa', name: 'Despensa'),
  ];

  /// Nombres de los 5 productos de demostración de cada categoría.
  static const Map<String, List<String>> productsByCategory =
      <String, List<String>>{
    'cat-bebidas': <String>[
      'Astra-Cola Original 500 ml',
      'Agua original 600 ml',
      'Jugo de naranja 500 ml',
      'Té de durazno 400 ml',
      'Bebida de limón 500 ml',
    ],
    'cat-snacks': <String>[
      'Papas naturales 45 g',
      'Nachos de maíz 60 g',
      'Maní salado 50 g',
      'Palomitas 40 g',
      'Galletas saladas 80 g',
    ],
    'cat-postres': <String>[
      'Brownie de chocolate 60 g',
      'Flan de vainilla 100 g',
      'Gelatina de fresa 120 g',
      'Arroz con leche 150 g',
      'Ponqué de vainilla 70 g',
    ],
    'cat-lacteos': <String>[
      'Leche entera 1 L',
      'Yogur de fresa 200 ml',
      'Queso fresco 250 g',
      'Kumis 200 ml',
      'Bebida láctea de chocolate 200 ml',
    ],
    'cat-cuidado': <String>[
      'Jabón corporal 125 g',
      'Crema dental 75 ml',
      'Champú 200 ml',
      'Desodorante 50 ml',
      'Cepillo dental suave',
    ],
    'cat-hogar': <String>[
      'Detergente 500 g',
      'Lavaloza 500 ml',
      'Esponja de cocina',
      'Bolsas de basura paquete x10',
      'Limpiador de pisos 1 L',
    ],
    'cat-mascotas': <String>[
      'Alimento para perro 500 g',
      'Alimento para gato 500 g',
      'Premios para perro 100 g',
      'Arena para gato 1 kg',
      'Juguete pelota para mascota',
    ],
    'cat-despensa': <String>[
      'Arroz 500 g',
      'Pasta 250 g',
      'Azúcar 500 g',
      'Aceite vegetal 500 ml',
      'Lentejas 500 g',
    ],
  };

  /// Prefijo de código por categoría (formato `MERCA-DEMO-{PREFIJO}-{NNN}`).
  static const Map<String, String> codePrefix = <String, String>{
    'cat-bebidas': 'BEB',
    'cat-snacks': 'SNK',
    'cat-postres': 'POS',
    'cat-lacteos': 'LAC',
    'cat-cuidado': 'CUI',
    'cat-hogar': 'HOG',
    'cat-mascotas': 'MAS',
    'cat-despensa': 'DES',
  };

  /// Categorías en el formato de la caché local de la app.
  static List<Map<String, dynamic>> categoryRows() {
    return categories
        .map(
          (({String id, String name}) category) => <String, dynamic>{
            'id': category.id,
            'name': category.name,
            'isActive': true,
          },
        )
        .toList();
  }

  /// Productos en el formato de la caché local de la app.
  static List<Map<String, dynamic>> productRows() {
    final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];
    int price = 2000;
    for (final ({String id, String name}) category in categories) {
      final List<String> names = productsByCategory[category.id]!;
      for (int i = 0; i < names.length; i++) {
        rows.add(<String, dynamic>{
          'id': '${category.id}-prod-${i + 1}',
          'name': names[i],
          'description': 'Producto de demostración para pruebas académicas',
          'categoryId': category.id,
          'category': <String, dynamic>{
            'id': category.id,
            'name': category.name,
            'isActive': true,
          },
          'price': price,
          'stock': 50,
          'isActive': true,
          'isDemo': true,
          'imageUrl': null,
          'codes': <String>[
            'MERCA-DEMO-${codePrefix[category.id]}-${(i + 1).toString().padLeft(3, '0')}',
          ],
        });
        price += 500;
      }
    }
    return rows;
  }

  /// Construye un repositorio de catálogo con los fixtures ya cargados.
  static Future<CatalogRepository> buildRepository({
    InMemoryStore? store,
  }) async {
    final InMemoryStore target = store ?? InMemoryStore();
    await target.writeString(
      'mercamigo.catalog.cache',
      jsonEncode(<String, dynamic>{
        'categorias': categoryRows(),
        'products': productRows(),
      }),
    );
    final CatalogRepository repository = CatalogRepository(store: target);
    await repository.refresh();
    return repository;
  }

  /// Categorías como objetos del modelo.
  static List<ProductCategory> modelCategories() {
    return categories
        .map(
          (({String id, String name}) category) => ProductCategory(
            id: category.id,
            name: category.name,
            isActive: true,
          ),
        )
        .toList();
  }

  /// Primer producto del catálogo como objeto del modelo.
  static Product firstProduct(CatalogRepository repository) =>
      repository.all.first;
}
