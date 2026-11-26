/// Tipo de regla promocional aplicada a un producto.
enum PromotionType {
  /// "2x1": por cada 2 unidades se cobra 1 (las unidades impares se pagan).
  twoForOne,

  /// "3x2": se pagan 2 por cada 3 unidades.
  threeForTwo,

  /// "3x$6.500": un paquete de 3 unidades tiene un precio fijo.
  bundlePrice,
}

/// Promoción aplicable a un producto.
///
/// Las reglas son reales y deterministas: se aplican sobre la cantidad que el
/// usuario eligió y el descuento se refleja en el subtotal y en el total de
/// la orden.
class Promotion {
  const Promotion({
    required this.id,
    required this.title,
    required this.type,
    required this.description,
    this.bundleQuantity = 2,
    this.bundlePrice,
    this.bannerImageUrl,
  });

  final String id;

  /// Texto corto visible en la interfaz ("2x1", "3x$6.500").
  final String title;

  final PromotionType type;
  final String description;

  /// Cantidad de unidades que forman el paquete.
  final int bundleQuantity;

  /// Precio total del paquete (solo para [PromotionType.bundlePrice]).
  final int? bundlePrice;

  /// Banner opcional definido por el administrador.
  final String? bannerImageUrl;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'type': type.name,
    'description': description,
    'bundleQuantity': bundleQuantity,
    'bundlePrice': bundlePrice,
    'bannerImageUrl': bannerImageUrl,
  };

  factory Promotion.fromJson(Map<String, dynamic> json) {
    final String rawType = json['type'] as String? ?? 'twoForOne';
    final PromotionType type = PromotionType.values.firstWhere(
      (PromotionType value) => value.name == rawType,
      orElse: () => PromotionType.twoForOne,
    );
    return Promotion(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      type: type,
      description: json['description'] as String? ?? '',
      bundleQuantity: (json['bundleQuantity'] as num?)?.toInt() ?? 2,
      bundlePrice: (json['bundlePrice'] as num?)?.toInt(),
      bannerImageUrl: json['bannerImageUrl'] as String?,
    );
  }

  factory Promotion.fromDatabase(Map<String, dynamic> row) {
    final String type = row['tipo'] as String? ?? 'dos_por_uno';
    final int buy = (row['cantidad_compra'] as num?)?.toInt() ?? 2;
    final int free = (row['cantidad_gratis'] as num?)?.toInt() ?? 1;
    final int packageQty = (row['cantidad_paquete'] as num?)?.toInt() ?? 2;
    final int? price = (row['precio_paquete_cop'] as num?)?.toInt();
    final PromotionType promotionType;
    final String title;
    if (type == 'tres_por_dos') {
      promotionType = PromotionType.threeForTwo;
      title = '3x2';
    } else if (type == 'precio_paquete') {
      promotionType = PromotionType.bundlePrice;
      title = '${packageQty}x\$${price ?? 0}';
    } else {
      promotionType = PromotionType.twoForOne;
      title = '2x1';
    }
    return Promotion(
      id: row['id'] as String? ?? '',
      title: title,
      type: promotionType,
      description: row['nombre'] as String? ?? title,
      bundleQuantity: type == 'precio_paquete' ? packageQty : buy + free,
      bundlePrice: price,
      bannerImageUrl: row['banner_url'] as String?,
    );
  }

  /// Calcula el costo a pagar por [quantity] unidades aplicando la regla.
  ///
  /// - [twoForOne]: se cobran `ceil(quantity / 2)` unidades.
  /// - [bundlePrice]: cada grupo completo de [bundleQuantity] unidades se
  ///   cobra a [bundlePrice]; el resto se cobra a precio normal.
  int payableAmount(int quantity, int unitPrice) {
    if (quantity <= 0) return 0;
    switch (type) {
      case PromotionType.twoForOne:
        final int chargedUnits = (quantity + 1) ~/ 2;
        return chargedUnits * unitPrice;
      case PromotionType.threeForTwo:
        final int bundles = quantity ~/ 3;
        final int remainder = quantity % 3;
        return (bundles * 2 + remainder) * unitPrice;
      case PromotionType.bundlePrice:
        final int? bundle = bundlePrice;
        if (bundle == null) return quantity * unitPrice;
        final int bundles = quantity ~/ bundleQuantity;
        final int remainder = quantity % bundleQuantity;
        return bundles * bundle + remainder * unitPrice;
    }
  }

  /// Ahorro generado por la promoción para [quantity] unidades.
  int savings(int quantity, int unitPrice) {
    final int gross = quantity * unitPrice;
    final int payable = payableAmount(quantity, unitPrice);
    final int result = gross - payable;
    return result < 0 ? 0 : result;
  }
}

/// Promociones registradas por id.
///
/// El catálogo actual de Supabase no tiene promociones (el esquema no tiene
/// columnas para ellas), así que esta lista está vacía en producción. Se
/// mantiene para que, cuando se añada una migración con promociones, el
/// carrito y el resumen ya sepan aplicar la regla.
abstract final class DemoPromotions {
  static Promotion? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final Promotion promotion in DemoPromotionCatalog.all) {
      if (promotion.id == id) return promotion;
    }
    return null;
  }

  static Promotion? fromJson(dynamic value) {
    if (value is Map<String, dynamic>) return Promotion.fromJson(value);
    return byId(value as String?);
  }
}

/// Catálogo de promociones conocidas por la app.
abstract final class DemoPromotionCatalog {
  static const Promotion astraTwoForOne = Promotion(
    id: 'PROMO-ASTRA-2X1',
    title: '2x1',
    type: PromotionType.twoForOne,
    description: 'Por cada 2 unidades de Astra Cola Original se cobra 1.',
    bundleQuantity: 2,
  );

  static const Promotion aguaThreeForSixFive = Promotion(
    id: 'PROMO-AGUA-3X6500',
    title: r'3x$6.500',
    type: PromotionType.bundlePrice,
    description: r'3 botellas de agua original por $6.500.',
    bundleQuantity: 3,
    bundlePrice: 6500,
  );

  static const Promotion dogChowTwoForOne = Promotion(
    id: 'PROMO-DOGCHOW-2X1',
    title: '2x1',
    type: PromotionType.twoForOne,
    description: 'Por comprar un paquete de comida "DogChow" llevas la segunda unidad gratis.',
    bundleQuantity: 2,
  );

  static const List<Promotion> all = <Promotion>[
    astraTwoForOne,
    aguaThreeForSixFive,
    dogChowTwoForOne,
  ];
}
