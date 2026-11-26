import 'package:flutter/foundation.dart';

import '../data/models/cart_item.dart';
import '../data/models/product.dart';
import '../repositories/cart_repository.dart';
import '../repositories/catalog_repository.dart';

/// Estado del carrito de compras.
///
/// El mismo carrito se usa tanto desde el catálogo como desde el escáner.
/// Todos los importes se calculan a partir de los datos de los productos
/// (enteros en COP), nunca con valores fijos.
class CartController extends ChangeNotifier {
  CartController({
    required this.cartRepository,
    required this.catalogRepository,
  });

  final CartRepository cartRepository;
  final CatalogRepository catalogRepository;

  final List<CartItem> _items = <CartItem>[];

  /// Líneas del carrito (solo lectura).
  List<CartItem> get items => List<CartItem>.unmodifiable(_items);

  bool get isEmpty => _items.isEmpty;

  bool get isNotEmpty => _items.isNotEmpty;

  /// Total de unidades en el carrito.
  int get totalUnits =>
      _items.fold<int>(0, (int sum, CartItem item) => sum + item.quantity);

  /// Subtotal sin promociones.
  int get subtotal =>
      _items.fold<int>(0, (int sum, CartItem item) => sum + item.grossTotal);

  /// Total de descuentos aplicados por las promociones.
  int get discount =>
      _items.fold<int>(0, (int sum, CartItem item) => sum + item.discount);

  /// Total a pagar en caja.
  int get total =>
      _items.fold<int>(0, (int sum, CartItem item) => sum + item.payableTotal);

  /// Restaura el carrito guardado localmente.
  Future<void> load() async {
    final List<CartItem> stored = await cartRepository.loadItems();
    _items
      ..clear()
      ..addAll(stored);
    notifyListeners();
  }

  /// Agrega un producto al carrito.
  ///
  /// Si el producto ya existe, suma la cantidad en la misma línea.
  Future<void> add(Product product, {int quantity = 1}) async {
    if (quantity <= 0) return;
    final int maxQuantity = product.stock > 0 ? product.stock : 1;
    final int index =
        _items.indexWhere((CartItem item) => item.productId == product.id);
    if (index >= 0) {
      final CartItem current = _items[index];
      final int newQuantity =
          (current.quantity + quantity).clamp(1, maxQuantity);
      _items[index] = current.copyWith(quantity: newQuantity);
    } else {
      _items.add(
        CartItem.fromProduct(product, quantity: quantity.clamp(1, maxQuantity)),
      );
    }
    notifyListeners();
    await _persist();
  }

  /// Aumenta en una unidad la cantidad de una línea.
  Future<void> increase(String productId) async {
    final int index =
        _items.indexWhere((CartItem item) => item.productId == productId);
    if (index < 0) return;
    final CartItem current = _items[index];
    final Product? product = catalogRepository.byId(productId);
    final int maxQuantity =
        product != null && product.stock > 0 ? product.stock : 999;
    if (current.quantity >= maxQuantity) return;
    _items[index] = current.copyWith(quantity: current.quantity + 1);
    notifyListeners();
    await _persist();
  }

  /// Disminuye en una unidad la cantidad de una línea.
  ///
  /// Si la cantidad llega a 0, la línea se elimina del carrito.
  Future<void> decrease(String productId) async {
    final int index =
        _items.indexWhere((CartItem item) => item.productId == productId);
    if (index < 0) return;
    final CartItem current = _items[index];
    if (current.quantity <= 1) {
      await remove(productId);
      return;
    }
    _items[index] = current.copyWith(quantity: current.quantity - 1);
    notifyListeners();
    await _persist();
  }

  /// Elimina una línea del carrito.
  Future<void> remove(String productId) async {
    _items.removeWhere((CartItem item) => item.productId == productId);
    notifyListeners();
    await _persist();
  }

  /// Vacía el carrito (se usa tras guardar el pedido con éxito).
  Future<void> clear() async {
    _items.clear();
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() => cartRepository.saveItems(_items);
}
