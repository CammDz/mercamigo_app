import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

/// Motivo por el que no se pudo obtener la ubicación del usuario.
enum LocationFailure {
  /// El GPS está apagado en el dispositivo.
  serviceDisabled,

  /// El usuario rechazó el permiso (puede volver a pedirlo).
  permissionDenied,

  /// El usuario marcó el permiso como "no preguntar más".
  permissionDeniedForever,

  /// La búsqueda de posición falló o tardó demasiado.
  unavailable,
}

/// Resultado de intentar obtener la ubicación del usuario.
class LocationResult {
  const LocationResult.success(this.latitude, this.longitude, {this.accuracy})
    : failure = null;

  const LocationResult.failure(this.failure)
    : latitude = null,
      longitude = null,
      accuracy = null;

  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final LocationFailure? failure;

  bool get isSuccess => failure == null;

  String get errorMessage => switch (failure) {
    LocationFailure.serviceDisabled =>
      'El GPS está apagado. Actívalo para usar tu ubicación.',
    LocationFailure.permissionDenied =>
      'Permiso de ubicación denegado. Actívalo en los ajustes del sistema.',
    LocationFailure.permissionDeniedForever => 'El permiso de ubicación está bloqueado. Habilítalo en los ajustes de la app.',
    LocationFailure.unavailable =>
      'No se pudo obtener la ubicación en este momento.',
    null => '',
  };
}

/// Servicio de ubicación del usuario.
///
/// El permiso solo se pide cuando el usuario usa explícitamente esta función
/// (nunca al iniciar la app ni en segundo plano).
class LocationService {
  const LocationService();

  /// Indica si el servicio de ubicación (GPS) está activo.
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  /// Permiso actual sin pedirlo.
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  /// Solicita el permiso de ubicación (solo foreground).
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  /// Obtiene la posición actual del usuario.
  Future<LocationResult> currentPosition() async {
    // El permiso se pide siempre que falte (Android muestra el diálogo si el
    // usuario no lo ha bloqueado). Se pide antes de mirar el GPS para que el
    // aviso del sistema no dependa de que el GPS esté encendido.
    LocationPermission permission = await checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return const LocationResult.failure(LocationFailure.permissionDenied);
    }
    if (permission == LocationPermission.deniedForever) {
      return const LocationResult.failure(
        LocationFailure.permissionDeniedForever,
      );
    }

    final bool serviceEnabled = await isServiceEnabled();
    if (!serviceEnabled) {
      return const LocationResult.failure(LocationFailure.serviceDisabled);
    }

    try {
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 20));
      return LocationResult.success(
        position.latitude,
        position.longitude,
        accuracy: position.accuracy,
      );
    } on TimeoutException {
      return const LocationResult.failure(LocationFailure.unavailable);
    } on Exception {
      return const LocationResult.failure(LocationFailure.unavailable);
    }
  }

  /// Abre la aplicación de mapas con la ruta a la tienda.
  ///
  /// Devuelve `false` si no hay ninguna app de mapas capaz de abrir el URI.
  Future<bool> openDirections({
    required double latitude,
    required double longitude,
    String? label,
  }) async {
    final String query = label == null || label.trim().isEmpty
        ? '$latitude,$longitude'
        : '$latitude,$longitude(${Uri.encodeComponent(label.trim())})';

    final Uri geoUri = Uri.parse('geo:$latitude,$longitude?q=$query');
    if (await canLaunchUrl(geoUri)) {
      return launchUrl(geoUri, mode: LaunchMode.externalApplication);
    }

    final Uri webUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$query',
    );
    if (await canLaunchUrl(webUri)) {
      return launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
    return false;
  }
}
