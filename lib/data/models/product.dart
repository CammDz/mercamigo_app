import 'product_category.dart';
import 'promotion.dart';

/// Código registrado de un producto (`codigos_producto`).
///
/// El tipo es siempre `barras`: el servidor genera el código principal al
/// crear el producto y la app lo dibuja con Code 128.
class ProductCode {
  const ProductCode({required this.code, required this.type});

  /// `codigos_producto.codigo` (texto: conserva los ceros iniciales).
  final String code;

  /// `codigos_producto.tipo`: la base solo admite `barras`.
  final String type;

  /// `true` si el código es de barras.
  bool get isBarcode => type.trim().toLowerCase() == 'barras';

  @override
  String toString() => 'ProductCode($code, $type)';
}

/// Producto del catálogo.
///
/// Refleja la tabla `public.productos` del proyecto Supabase y sus códigos
/// registrados en `public.codigos_producto`.
///
/// - `precio_cop` -> [price] (pesos colombianos, entero).
/// - `stock_demo` -> [stock] (inventario de demostración, no real).
/// - `es_demostracion` -> [isDemo].
/// - `imagen_url` -> [imageUrl] (foto del producto, local o remota).
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.description,
    required this.categoryId,
    required this.category,
    required this.price,
    required this.stock,
    required this.isActive,
    required this.isDemo,
    this.imageUrl,
    this.codes = const <ProductCode>[],
    this.promotion,
  });

  /// `productos.id` (uuid).
  final String id;

  final String name;
  final String description;

  /// `productos.categoria_id` (uuid).
  final String categoryId;

  final ProductCategory category;

  /// `productos.precio_cop`.
  final int price;

  /// `productos.stock_demo`.
  final int stock;

  /// `productos.activo`.
  final bool isActive;

  /// `productos.es_demostracion`.
  final bool isDemo;

  /// `productos.imagen_url` (puede venir vacía).
  final String? imageUrl;

  /// `codigos_producto` asociados a este producto (con su tipo).
  final List<ProductCode> codes;

  /// Promoción aplicable, si el producto la tiene.
  final Promotion? promotion;

  bool get inStock => stock > 0;

  /// Todos los códigos con los que se puede identificar el producto.
  List<String> get registeredCodes =>
      codes.map((ProductCode code) => code.code).toList(growable: false);

  /// Primer código registrado del producto (el principal).
  ///
  /// El código se dibuja localmente como Code 128, así que no depende de una
  /// Edge Function ni de Internet.
  ProductCode? get registeredCode => codes.isEmpty ? null : codes.first;

  /// `true` si el producto tiene algún código registrado.
  bool get hasRegisteredCode => codes.isNotEmpty;

  /// Recurso **local** de la foto del producto.
  ///
  /// Solo se usa cuando la foto elegida por el administrador es un recurso
  /// empaquetado (`assets/...`). Si la foto es remota (la que se sube desde
  /// el celular) se muestra con `Image.network`, y si el producto no tiene
  /// foto propia se muestra un placeholder neutro.
  String? get localImageAsset {
    final String? chosen = imageUrl;
    if (chosen != null && chosen.startsWith('assets/')) return chosen;
    return null;
  }

  /// `true` si la foto del producto está en Supabase Storage.
  bool get hasRemoteImage {
    final String? chosen = imageUrl;
    return chosen != null && chosen.startsWith('http');
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'description': description,
    'categoryId': categoryId,
    'category': category.toJson(),
    'price': price,
    'stock': stock,
    'isActive': isActive,
    'isDemo': isDemo,
    'imageUrl': imageUrl,
    'codes': codes
        .map(
          (ProductCode code) => <String, dynamic>{
            'code': code.code,
            'type': code.type,
          },
        )
        .toList(growable: false),
    'promotion': promotion?.toJson(),
  };

  static Product fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      categoryId: json['categoryId'] as String? ?? '',
      category: ProductCategory.fromJson(
        (json['category'] as Map<String, dynamic>?) ??
            const <String, dynamic>{},
      ),
      price: (json['price'] as num?)?.toInt() ?? 0,
      stock: (json['stock'] as num?)?.toInt() ?? 0,
      isActive: json['isActive'] as bool? ?? true,
      isDemo: json['isDemo'] as bool? ?? true,
      imageUrl: json['imageUrl'] as String?,
      codes: (json['codes'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic raw) {
            if (raw is String) return ProductCode(code: raw, type: 'barras');
            if (raw is Map<String, dynamic>) {
              return ProductCode(
                code: raw['code'] as String? ?? '',
                type: raw['type'] as String? ?? 'barras',
              );
            }
            return null;
          })
          .whereType<ProductCode>()
          .toList(growable: false),
      promotion: DemoPromotions.fromJson(json['promotion']),
    );
  }
}
