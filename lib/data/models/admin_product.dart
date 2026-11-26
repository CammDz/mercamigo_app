/// Código registrado de un producto (`codigos_producto`).
///
/// El código se guarda **como texto** en la base de datos para conservar los
/// ceros iniciales de un código de barras ("0123456789012").
///
/// Este modelo es solo de la vista de administración: el comprador nunca ve
/// la lista de códigos de otros productos.
class ProductCode {
  const ProductCode({
    required this.id,
    required this.code,
    required this.type,
  });

  /// `codigos_producto.id` (uuid). Necesario para corregir el código.
  final String id;

  /// `codigos_producto.codigo`.
  final String code;

  /// `codigos_producto.tipo`: la base solo admite `barras`.
  final String type;

  /// `true` si el código es de barras.
  bool get isBarcode => type == 'barras';

  /// Etiqueta legible del tipo de código.
  String get typeLabel => 'Código de barras';

  @override
  String toString() => 'ProductCode($code, $type)';
}

/// Producto con su estado y sus códigos, tal y como lo ve el administrador.
///
/// A diferencia de [Product] (el modelo del comprador) este modelo **sí**
/// incluye los productos inactivos y el identificador de cada código, que
/// hacen falta para desactivar, reactivar y corregir.
class AdminProduct {
  const AdminProduct({
    required this.id,
    required this.name,
    required this.description,
    required this.categoryId,
    required this.categoryName,
    required this.price,
    required this.isActive,
    this.imageUrl,
    this.codes = const <ProductCode>[],
  });

  final String id;
  final String name;
  final String description;
  final String categoryId;
  final String categoryName;
  final int price;
  final bool isActive;
  final String? imageUrl;
  final List<ProductCode> codes;

  /// Texto con los códigos registrados (para la lista resumida).
  String get codesLabel =>
      codes.isEmpty ? 'Sin códigos' : codes.map((ProductCode c) => c.code).join(', ');
}

/// Tienda configurada, tal y como la ve el administrador.
class AdminStore {
  const AdminStore({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.isActive,
  });

  /// `tiendas.id`. Es `null` si todavía no hay ninguna tienda.
  final String? id;

  final String name;
  final String address;
  final double? latitude;
  final double? longitude;
  final bool isActive;

  /// `true` cuando hay coordenadas guardadas.
  bool get hasCoordinates => latitude != null && longitude != null;
}
