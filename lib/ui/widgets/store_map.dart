import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';

/// Mapa de la tienda.
///
/// · En **modo consulta** ([onPick] == null) el marcador de la tienda NO es
///   arrastrable, tocar el mapa NO cambia las coordenadas y mover o ampliar
///   el mapa solo cambia la vista. Las coordenadas que se muestran son
///   siempre las guardadas en el servidor.
/// · En **modo edición** ([onPick] != null) el administrador puede elegir el
///   punto: tocando el mapa o arrastrando el marcador se llama a [onPick]
///   con el nuevo punto. El guardado lo decide el formulario, no el mapa.
///
/// La posición del usuario (su GPS) se puede mostrar como un marcador
/// aparte: representa dónde está el cliente y **nunca** sustituye la
/// ubicación de la tienda.
class StoreMap extends StatefulWidget {
  const StoreMap({
    super.key,
    required this.latitude,
    required this.longitude,
    this.onPick,
    this.userLatitude,
    this.userLongitude,
    this.height = 250,
  });

  /// Latitud de la tienda (null si no está configurada).
  final double? latitude;

  /// Longitud de la tienda (null si no está configurada).
  final double? longitude;

  /// Si es `null` el mapa es de solo consulta.
  final ValueChanged<LatLng>? onPick;

  /// Latitud del usuario (solo informativa).
  final double? userLatitude;

  /// Longitud del usuario (solo informativa).
  final double? userLongitude;

  /// Alto del mapa.
  final double height;

  @override
  State<StoreMap> createState() => _StoreMapState();
}

class _StoreMapState extends State<StoreMap> {
  final MapController _controller = MapController();

  bool get _editable => widget.onPick != null;

  LatLng? get _storePoint {
    final double? latitude = widget.latitude;
    final double? longitude = widget.longitude;
    if (latitude == null || longitude == null) return null;
    return LatLng(latitude, longitude);
  }

  LatLng? get _userPoint {
    final double? latitude = widget.userLatitude;
    final double? longitude = widget.userLongitude;
    if (latitude == null || longitude == null) return null;
    return LatLng(latitude, longitude);
  }

  @override
  void didUpdateWidget(covariant StoreMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final LatLng? store = _storePoint;
    final LatLng? user = _userPoint;

    // Si la posición del cliente aparece (o cambia), se ajusta la vista para
    // que se vean las dos marcas: la tienda y el usuario.
    final bool userChanged =
        user != null &&
        (oldWidget.userLatitude != widget.userLatitude ||
            oldWidget.userLongitude != widget.userLongitude);
    if (userChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (store == null) {
          _controller.move(user, 15);
        } else {
          _fitStoreAndUser(store, user);
        }
      });
      return;
    }

    // Si el punto de la tienda cambia (por ejemplo, el administrador elige
    // otro) se recentra el mapa sin cambiar el nivel de zoom.
    if (store == null) return;
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _controller.move(store, _controller.camera.zoom);
      });
    }
  }

  /// Ajusta la vista para que se vean la tienda y el cliente.
  void _fitStoreAndUser(LatLng store, LatLng user) {
    final double distance = _distanceInMeters(store, user);
    // Si están muy lejos, centrar en el cliente: la tienda saldría de la
    // pantalla y el usuario no vería su posición.
    if (distance > 800) {
      _controller.move(user, 15);
      return;
    }
    _controller.fitCamera(
      CameraFit.coordinates(
        coordinates: <LatLng>[store, user],
        padding: const EdgeInsets.all(48),
        maxZoom: 16,
      ),
    );
  }

  /// Distancia aproximada entre dos puntos (fórmula del haversine).
  static double _distanceInMeters(LatLng a, LatLng b) {
    const double earthRadius = 6371000;
    final double dLat = _radians(b.latitude - a.latitude);
    final double dLon = _radians(b.longitude - a.longitude);
    final double h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radians(a.latitude)) *
            math.cos(_radians(b.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * earthRadius * math.asin(math.min(1, math.sqrt(h)));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;

  void _pick(LatLng point) {
    widget.onPick?.call(point);
  }

  @override
  Widget build(BuildContext context) {
    final LatLng? store = _storePoint;
    final LatLng? user = _userPoint;

    if (store == null) {
      return Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: AppColors.surfaceSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'Todavía no hay una ubicación configurada para la tienda.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: <Widget>[
            FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: store,
                initialZoom: 16,
                // En modo consulta NO se registra ningún `onTap`: tocar el
                // mapa no puede cambiar las coordenadas de la tienda.
                onTap: _editable
                    ? (TapPosition tapPosition, LatLng point) => _pick(point)
                    : null,
              ),
              children: <Widget>[
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.mercamigo.mercamigo_app',
                  tileProvider: NetworkTileProvider(),
                ),
                MarkerLayer(
                  markers: <Marker>[
                    if (user != null)
                      Marker(
                        point: user,
                        width: 18,
                        height: 18,
                        child: const _UserDot(),
                      ),
                    Marker(
                      point: store,
                      width: 42,
                      height: 42,
                      alignment: Alignment.topCenter,
                      child: _StoreMarker(
                        draggable: _editable,
                        controller: _controller,
                        onDrag: _pick,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              left: 8,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _editable
                      ? 'Toca el mapa o arrastra el marcador para elegir el punto'
                      : 'Ubicación guardada de la tienda',
                  style: const TextStyle(fontSize: 10.5, color: AppColors.ink),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Marcador de la tienda.
///
/// En modo consulta **no** tiene gestos de arrastre: el marcador no se
/// puede mover.
class _StoreMarker extends StatelessWidget {
  const _StoreMarker({
    required this.draggable,
    required this.controller,
    required this.onDrag,
  });

  final bool draggable;
  final MapController controller;
  final ValueChanged<LatLng> onDrag;

  @override
  Widget build(BuildContext context) {
    final Widget pin = Container(
      decoration: BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(Icons.storefront, color: Colors.white, size: 20),
    );

    if (!draggable) return pin;

    return GestureDetector(
      onPanUpdate: (DragUpdateDetails details) {
        // `screenOffsetToLatLng` trabaja en coordenadas de pantalla.
        final LatLng point = controller.camera.screenOffsetToLatLng(
          details.globalPosition,
        );
        onDrag(point);
      },
      child: pin,
    );
  }
}

/// Punto azul de la posición del usuario (informativa).
class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF4285F4),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }
}
