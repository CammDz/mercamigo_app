import 'package:flutter/foundation.dart';

import '../data/models/product.dart';
import '../data/models/product_category.dart';
import '../repositories/catalog_repository.dart';

/// Estado de la búsqueda y del filtro por categoría.
///
/// La búsqueda es **global**: cuando hay texto de búsqueda, los resultados
/// provienen de todo el catálogo, no solo de la categoría abierta.
class CatalogController extends ChangeNotifier {
  CatalogController({required this.catalogRepository});

  final CatalogRepository catalogRepository;

  String _query = '';
  ProductCategory? _category;
  bool _loading = false;

  /// Texto de la búsqueda global actual.
  String get query => _query;

  /// Categoría abierta (null = todas).
  ProductCategory? get category => _category;

  /// Indica si hay una búsqueda activa.
  bool get isSearching => _query.trim().isNotEmpty;

  /// Todos los productos del catálogo.
  List<Product> get all => catalogRepository.all;

  /// Categorías activas del catálogo.
  List<ProductCategory> get categories => catalogRepository.activeCategories;

  /// Resultados de la búsqueda global (todo el catálogo).
  List<Product> get searchResults => catalogRepository.search(_query);

  /// Productos de la categoría abierta.
  List<Product> get categoryProducts => _category == null
      ? catalogRepository.all
      : catalogRepository.byCategory(_category!);

  /// Productos que se muestran en pantalla según el estado actual.
  List<Product> get visibleProducts =>
      isSearching ? searchResults : categoryProducts;

  /// Productos que tienen alguna promoción configurada.
  List<Product> get productsWithPromotion => catalogRepository.productsWithPromotion;

  /// `true` mientras se sincroniza el catálogo con el servidor.
  bool get isLoading => _loading;

  /// `true` cuando el catálogo actual viene del servidor.
  bool get isOnline => catalogRepository.isOnline;

  /// �sltimo error de sincronización.
  String? get lastError => catalogRepository.lastError;

  /// `true` cuando no hay ningún producto cargado.
  bool get isEmpty => catalogRepository.all.isEmpty;

  /// Sincroniza el catálogo con el servidor (y actualiza la caché local).
  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    await catalogRepository.refresh();
    _loading = false;
    notifyListeners();
  }

  /// Fija el texto de la búsqueda global.
  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    notifyListeners();
  }

  /// Abre (o cierra) una categoría.
  void setCategory(ProductCategory? value) {
    if (_category == value) return;
    _category = value;
    notifyListeners();
  }

  /// Limpia la búsqueda y el filtro.
  void clear() {
    _query = '';
    _category = null;
    notifyListeners();
  }
}
