import 'package:flutter/foundation.dart';

import '../data/models/store_location.dart';
import '../repositories/settings_repository.dart';
import '../services/location_service.dart';

/// Estado de la configuración de la tienda y de la ubicación del usuario.
///
/// El permiso de ubicación del usuario solo se solicita cuando el usuario
/// pulsa explícitamente "Usar mi ubicación".
class StoreLocationController extends ChangeNotifier {
  StoreLocationController({
    required this.settingsRepository,
    LocationService? locationService,
  }) : locationService = locationService ?? const LocationService();

  final SettingsRepository settingsRepository;
  final LocationService locationService;

  StoreLocation _location = const StoreLocation();
  double? _userLatitude;
  double? _userLongitude;
  LocationFailure? _locationFailure;
  bool _requestingLocation = false;
  bool _loaded = false;

  /// `true` cuando ya se han cargado los datos de la tienda.
  ///
  /// La pantalla de ubicación no permite registrar nada hasta que la
  /// configuración del servidor (o la local) está cargada.
  bool get isLoaded => _loaded;

  /// Configuración actual de la tienda.
  StoreLocation get location => _location;

  /// `true` cuando hay nombre, dirección y coordenadas configuradas.
  bool get isConfigured => _location.isConfigured;

  /// `true` cuando la tienda viene del servidor y no se puede editar desde
  /// la app.
  bool get isFromServer => _location.isFromServer;

  /// Texto a mostrar cuando falta configuración.
  String get statusMessage => isConfigured
      ? (_location.name ?? 'Mercamigo')
      : StoreLocation.pendingMessage;

  /// Latitud del usuario (null si todavía no se solicitó).
  double? get userLatitude => _userLatitude;

  /// Longitud del usuario (null si todavía no se solicitó).
  double? get userLongitude => _userLongitude;

  /// Error de la última solicitud de ubicación.
  LocationFailure? get locationFailure => _locationFailure;

  bool get isRequestingLocation => _requestingLocation;

  /// Restaura la configuración (servidor primero, luego local).
  Future<void> load() async {
    _location = await settingsRepository.loadStoreLocation();
    _loaded = true;
    notifyListeners();
  }

  /// Guarda la configuración **local** de la tienda.
  ///
  /// Si la tienda viene del servidor, la app no la modifica: la configuración
  /// del servidor manda.
  Future<void> save({
    String? name,
    String? address,
    double? latitude,
    double? longitude,
  }) async {
    if (_location.isFromServer) return;
    _location = _location.copyWith(
      name: name,
      address: address,
      latitude: latitude,
      longitude: longitude,
    );
    notifyListeners();
    await settingsRepository.saveStoreLocation(_location);
  }

  /// Pide la ubicación del usuario (solo foreground, a petición del usuario).
  Future<LocationResult> requestUserLocation() async {
    if (_requestingLocation) {
      return const LocationResult.failure(LocationFailure.unavailable);
    }
    _requestingLocation = true;
    _locationFailure = null;
    notifyListeners();
    try {
      final LocationResult result = await locationService.currentPosition();
      if (result.isSuccess) {
        _userLatitude = result.latitude;
        _userLongitude = result.longitude;
      } else {
        _locationFailure = result.failure;
      }
      return result;
    } finally {
      _requestingLocation = false;
      notifyListeners();
    }
  }

  /// Abre "Cómo llegar" en la aplicación de mapas.
  Future<bool> openDirections() async {
    final double? latitude = _location.latitude;
    final double? longitude = _location.longitude;
    if (latitude == null || longitude == null) return false;
    return locationService.openDirections(
      latitude: latitude,
      longitude: longitude,
      label: _location.name,
    );
  }
}
