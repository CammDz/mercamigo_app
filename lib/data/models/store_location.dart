/// Configuración de la tienda.
///
/// Refleja la tabla `public.tiendas` del proyecto Supabase
/// (`nombre`, `direccion`, `latitud`, `longitud`, `activa`).
///
/// No se inventa ninguna ubicación real: mientras no haya una tienda activa
/// con coordenadas, la app muestra
/// "Ubicación de tienda pendiente de configurar" y no habilita "Cómo llegar".
class StoreLocation {
  const StoreLocation({
    this.id,
    this.name,
    this.address,
    this.latitude,
    this.longitude,
    this.isActive = false,
    this.isFromServer = false,
  });

  /// `tiendas.id` (uuid) cuando la tienda viene del servidor.
  final String? id;

  final String? name;
  final String? address;
  final double? latitude;
  final double? longitude;

  /// `tiendas.activa`.
  final bool isActive;

  /// `true` cuando la configuración viene del servidor y no se puede editar
  /// desde la app.
  final bool isFromServer;

  /// Indica si hay datos suficientes para ubicar la tienda.
  bool get hasCoordinates => latitude != null && longitude != null;

  /// Indica si la tienda está completamente configurada.
  bool get isConfigured =>
      (name != null && name!.trim().isNotEmpty) &&
      (address != null && address!.trim().isNotEmpty) &&
      hasCoordinates;

  /// Texto mostrado cuando falta configuración.
  static const String pendingMessage =
      'Ubicación de tienda pendiente de configurar';

  StoreLocation copyWith({
    String? name,
    String? address,
    double? latitude,
    double? longitude,
    bool? isActive,
    bool? isFromServer,
    bool clearCoordinates = false,
  }) {
    return StoreLocation(
      id: id,
      name: name ?? this.name,
      address: address ?? this.address,
      latitude: clearCoordinates ? null : (latitude ?? this.latitude),
      longitude: clearCoordinates ? null : (longitude ?? this.longitude),
      isActive: isActive ?? this.isActive,
      isFromServer: isFromServer ?? this.isFromServer,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
    'isActive': isActive,
    'isFromServer': isFromServer,
  };

  static StoreLocation fromJson(Map<String, dynamic> json) {
    return StoreLocation(
      id: json['id'] as String?,
      name: json['name'] as String?,
      address: json['address'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      isActive: json['isActive'] as bool? ?? false,
      isFromServer: json['isFromServer'] as bool? ?? false,
    );
  }
}
