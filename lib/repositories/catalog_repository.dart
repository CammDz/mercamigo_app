import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/text_normalizer.dart';
import '../data/local/key_value_store.dart';
import '../data/models/product.dart';
import '../data/models/product_category.dart';
import '../data/models/promotion.dart';

/// Acceso al catálogo de productos.
///
/// Implementación Against el proyecto Supabase: las categorías, los productos
/// y sus códigos se leen de `categorias`, `productos` y `codigos_producto`.
/// El resultado se guarda en caché local para que la app siga siendo
/// utilizable sin conexión.
class CatalogRepository {
  CatalogRepository({required this.store, this.client});

  static const String _cacheKey = 'mercamigo.catalog.cache';

  final KeyValueStore store;
  final SupabaseClient? client;

  List<ProductCategory> _categories = <ProductCategory>[];
  List<Product> _products = <Product>[];
  bool _isOnline = false;
  String? _lastError;

  /// Categorías cargadas.
  List<ProductCategory> get categories =>
      List<ProductCategory>.unmodifiable(_categories);

  /// Productos cargados.
  List<Product> get all => List<Product>.unmodifiable(_products);

  /// `true` cuando los datos actuales vienen del servidor.
  bool get isOnline => _isOnline;

  /// �sltimo error de sincronización (si lo hubo).
  String? get lastError => _lastError;

  /// Categorías activas, en el orden devuelto por el servidor.
  List<ProductCategory> get activeCategories => _categories
      .where((ProductCategory category) => category.isActive)
      .toList(growable: false);

  /// Carga el catálogo: primero la caché local y después el servidor.
  ///
  /// La llamada al servidor tiene **tiempo límite**: sin Internet la app
  /// sigue funcionando con la caché y no se queda cargando.
  Future<void> refresh() async {
    await _loadFromCache();
    if (client == null) return;
    try {
      await _loadFromServer().timeout(const Duration(seconds: 20));
      _isOnline = true;
      _lastError = null;
    } catch (error) {
      _isOnline = false;
      _lastError = '$error';
    }
  }

  Future<void> _loadFromCache() async {
    final String? raw = await store.readString(_cacheKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final List<dynamic> rawCategories =
          decoded['categorias'] as List<dynamic>? ?? const <dynamic>[];
      final List<dynamic> rawProducts =
          decoded['products'] as List<dynamic>? ?? const <dynamic>[];
      if (rawCategories.isEmpty && rawProducts.isEmpty) return;
      _categories = rawCategories
          .whereType<Map<String, dynamic>>()
          .map(ProductCategory.fromJson)
          .toList();
      _products = rawProducts
          .whereType<Map<String, dynamic>>()
          .map(Product.fromJson)
          .toList();
    } on FormatException {
      // Caché corrupta: se ignora y se vuelve a pedir al servidor.
    }
  }

  Future<void> _loadFromServer() async {
    final SupabaseClient client = this.client!;

    final categoriesResponse = await client
        .from('categorias')
        .select('id, nombre, activa');
    final Map<String, ProductCategory> categoriesById =
        <String, ProductCategory>{};
    for (final Map<String, dynamic> row
        in (categoriesResponse as List<dynamic>)
            .whereType<Map<String, dynamic>>()) {
      final ProductCategory category = ProductCategory(
        id: row['id'] as String? ?? '',
        name: row['nombre'] as String? ?? '',
        isActive: row['activa'] as bool? ?? true,
      );
      categoriesById[category.id] = category;
    }

    final productsResponse = await client
        .from('productos')
        .select(
          'id, nombre, descripcion, precio_cop, imagen_url, stock_demo, '
          'activo, es_demostracion, categoria_id, '
          'categoria:categorias(id, nombre, activa), '
          'codigos:codigos_producto(codigo, tipo), '
          'promo_links:promocion_productos!left(promocion:promociones!inner(id, nombre, tipo, '
          'cantidad_compra, cantidad_gratis, cantidad_paquete, precio_paquete_cop, banner_url, activa))',
        );

    final List<Product> products = <Product>[];
    for (final Map<String, dynamic> row
        in (productsResponse as List<dynamic>)
            .whereType<Map<String, dynamic>>()) {
      final String categoryId = row['categoria_id'] as String? ?? '';
      final ProductCategory category =
          categoriesById[categoryId] ??
          _categoryFromEmbed(row['categoria']) ??
          ProductCategory(id: categoryId, name: '', isActive: true);

      products.add(
        Product(
          id: row['id'] as String? ?? '',
          name: row['nombre'] as String? ?? '',
          description: row['descripcion'] as String? ?? '',
          categoryId: categoryId,
          category: category,
          price: (row['precio_cop'] as num?)?.toInt() ?? 0,
          stock: (row['stock_demo'] as num?)?.toInt() ?? 0,
          isActive: row['activo'] as bool? ?? true,
          isDemo: row['es_demostracion'] as bool? ?? true,
          imageUrl: row['imagen_url'] as String?,
          codes: _codesFromEmbed(row['codigos']),
          promotion: _promotionFromEmbed(row['promo_links']),
        ),
      );
    }

    _categories = categoriesById.values.toList();
    _products = products;
    await _saveToCache();
  }

  ProductCategory? _categoryFromEmbed(Object? embed) {
    final Map<String, dynamic>? row = embed is List
        ? (embed.isEmpty ? null : embed.first as Map<String, dynamic>)
        : (embed as Map<String, dynamic>?);
    if (row == null) return null;
    return ProductCategory(
      id: row['id'] as String? ?? '',
      name: row['nombre'] as String? ?? '',
      isActive: row['activa'] as bool? ?? true,
    );
  }

  List<ProductCode> _codesFromEmbed(Object? embed) {
    final List<Map<String, dynamic>> rows = embed is List
        ? embed.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[if (embed is Map<String, dynamic>) embed];
    return rows
        .map(
          (Map<String, dynamic> row) => ProductCode(
            code: row['codigo'] as String? ?? '',
            type: row['tipo'] as String? ?? 'barras',
          ),
        )
        .where((ProductCode code) => code.code.isNotEmpty)
        .toList(growable: false);
  }

  Promotion? _promotionFromEmbed(Object? embed) {
    final List<Map<String, dynamic>> links = embed is List
        ? embed.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[if (embed is Map<String, dynamic>) embed];
    for (final Map<String, dynamic> link in links) {
      final Object? raw = link['promocion'];
      final Map<String, dynamic>? row = raw is List
          ? (raw.isEmpty ? null : raw.first as Map<String, dynamic>)
          : raw as Map<String, dynamic>?;
      if (row != null && (row['activa'] as bool? ?? false)) {
        return Promotion.fromDatabase(row);
      }
    }
    return null;
  }

  Future<void> _saveToCache() async {
    final String raw = jsonEncode(<String, dynamic>{
      'categorias': _categories.map((ProductCategory c) => c.toJson()).toList(),
      'products': _products.map((Product p) => p.toJson()).toList(),
    });
    await store.writeString(_cacheKey, raw);
  }

  /// Busca un producto por su identificador.
  Product? byId(String id) {
    for (final Product product in _products) {
      if (product.id.toLowerCase() == id.toLowerCase()) return product;
    }
    return null;
  }

  /// Busca un producto por cualquier código registrado (`codigos_producto`).
  ///
  /// El valor leído se trata como un token opaco: nunca se interpreta como
  /// URL ni se ejecuta.
  Product? findByCode(String rawCode) {
    final String code = rawCode.trim();
    if (code.isEmpty) return null;
    final String needle = code.toLowerCase();
    for (final Product product in _products) {
      for (final String registered in product.registeredCodes) {
        if (registered.toLowerCase() == needle) return product;
      }
    }
    return null;
  }

  /// Productos de una categoría.
  List<Product> byCategory(ProductCategory category) {
    return _products
        .where((Product product) => product.categoryId == category.id)
        .toList(growable: false);
  }

  /// Búsqueda global por nombre y categoría (ignora mayúsculas y tildes).
  List<Product> search(String query) {
    final String normalized = normalizeText(query);
    if (normalized.isEmpty) return const <Product>[];
    return _products
        .where((Product product) {
          return containsNormalized(product.name, normalized) ||
              containsNormalized(product.category.name, normalized) ||
              containsNormalized(product.description, normalized);
        })
        .toList(growable: false);
  }

  /// Búsqueda global combinada con el filtro de categoría.
  List<Product> searchInCategory(String query, ProductCategory? category) {
    final List<Product> results = search(query);
    if (category == null) return results;
    return results
        .where((Product product) => product.categoryId == category.id)
        .toList(growable: false);
  }

  /// Productos que tienen alguna promoción configurada.
  List<Product> get productsWithPromotion => _products
      .where((Product product) => product.promotion != null)
      .toList(growable: false);
}
