/// Origen de la compra. Se elige una sola vez al inicio y se conserva durante
/// todo el recorrido hasta que se guarda en el pedido.
///
/// El valor `serverValue` es el que se guarda en `pedidos.origen`.
enum PurchaseOrigin {
  /// "Estoy en la tienda": el recorrido empieza por el escáner.
  inStore('en_tienda', 'En tienda', 'Escanea productos desde los anaqueles'),

  /// "Pedir desde donde estes": el recorrido empieza por el catálogo.
  pickup('para_recoger', 'Pedido para recoger', 'Explora secciones y agrega tu orden');

  const PurchaseOrigin(this.serverValue, this.label, this.description);

  /// Valor válido en `pedidos.origen`.
  final String serverValue;

  /// Texto corto visible.
  final String label;

  /// Texto descriptivo del prototipo.
  final String description;

  /// Texto mostrado en el resumen de la orden.
  String get summaryLabel => 'Origen: $label';

  static PurchaseOrigin fromServer(String? value) {
    return PurchaseOrigin.values.firstWhere(
      (PurchaseOrigin origin) => origin.serverValue == value,
      orElse: () => PurchaseOrigin.inStore,
    );
  }

  static PurchaseOrigin fromName(String? value) {
    return PurchaseOrigin.values.firstWhere(
      (PurchaseOrigin origin) => origin.name == value,
      orElse: () => PurchaseOrigin.inStore,
    );
  }
}
