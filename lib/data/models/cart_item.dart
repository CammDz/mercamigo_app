import 'product.dart';
import 'promotion.dart';

/// Línea del carrito.
///
/// Guarda una copia de los datos del producto para que el carrito siga siendo
/// coherente aunque el catálogo cambie, y para poder reconstruir el pedido.
class CartItem {
  const CartItem({
    required this.productId,
    required this.name,
    required this.categoryId,
    required this.unitPrice,
    required this.quantity,
    this.imageAsset,
    this.promotion,
  });

  factory CartItem.fromProduct(Product product, {int quantity = 1}) {
    return CartItem(
      productId: product.id,
      name: product.name,
      categoryId: product.categoryId,
      unitPrice: product.price,
      quantity: quantity,
      imageAsset: product.localImageAsset,
      promotion: product.promotion,
    );
  }

  final String productId;
  final String name;
  final String categoryId;

  /// Precio unitario base en COP.
  final int unitPrice;

  final int quantity;
  final String? imageAsset;
  final Promotion? promotion;

  /// Costo sin promoción (cantidad por precio unitario).
  int get grossTotal => unitPrice * quantity;

  /// Costo real a pagar de la línea aplicando la promoción (si existe).
  int get payableTotal =>
      promotion?.payableAmount(quantity, unitPrice) ?? grossTotal;

  /// Ahorro de la línea.
  int get discount => grossTotal - payableTotal;

  CartItem copyWith({int? quantity}) {
    return CartItem(
      productId: productId,
      name: name,
      categoryId: categoryId,
      unitPrice: unitPrice,
      quantity: quantity ?? this.quantity,
      imageAsset: imageAsset,
      promotion: promotion,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'productId': productId,
    'name': name,
    'categoryId': categoryId,
    'unitPrice': unitPrice,
    'quantity': quantity,
    'imageAsset': imageAsset,
    'promotion': promotion?.toJson(),
  };

  static CartItem fromJson(Map<String, dynamic> json) {
    return CartItem(
      productId: json['productId'] as String,
      name: json['name'] as String,
      categoryId: json['categoryId'] as String? ?? 'bebidas',
      unitPrice: (json['unitPrice'] as num?)?.toInt() ?? 0,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      imageAsset: json['imageAsset'] as String?,
      promotion: DemoPromotions.fromJson(json['promotion']),
    );
  }
}
