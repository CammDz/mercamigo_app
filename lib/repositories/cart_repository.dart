import 'dart:convert';

import '../data/local/key_value_store.dart';
import '../data/models/cart_item.dart';
import '../data/models/purchase_origin.dart';

/// Persistencia local del carrito y del origen de compra.
///
/// Se separa detrás de un repositorio para poder migrar a una API o base de
/// datos compartida sin rehacer las pantallas.
class CartRepository {
  CartRepository(this.store);

  static const String _itemsKey = 'mercamigo.cart.items';
  static const String _originKey = 'mercamigo.cart.origin';

  final KeyValueStore store;

  /// Carga las líneas guardadas.
  Future<List<CartItem>> loadItems() async {
    final String? raw = await store.readString(_itemsKey);
    if (raw == null || raw.isEmpty) return <CartItem>[];
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return <CartItem>[];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(CartItem.fromJson)
          .where((CartItem item) => item.quantity > 0)
          .toList();
    } on FormatException {
      return <CartItem>[];
    }
  }

  /// Guarda las líneas del carrito.
  Future<void> saveItems(List<CartItem> items) async {
    final String raw =
        jsonEncode(items.map((CartItem item) => item.toJson()).toList());
    await store.writeString(_itemsKey, raw);
  }

  /// Carga el origen de compra guardado (si lo hay).
  Future<PurchaseOrigin?> loadOrigin() async {
    final String? raw = await store.readString(_originKey);
    if (raw == null || raw.isEmpty) return null;
    return PurchaseOrigin.fromServer(raw);
  }

  /// Guarda el origen de compra.
  Future<void> saveOrigin(PurchaseOrigin origin) =>
      store.writeString(_originKey, origin.serverValue);

  /// Borra el carrito y el origen.
  Future<void> clear() async {
    await store.remove(_itemsKey);
    await store.remove(_originKey);
  }
}
