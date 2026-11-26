import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Estado del permiso de cámara, para poder explicarle al usuario qué
/// pasa y qué puede hacer.
enum CameraPermissionStatus {
  /// Todavía no se ha pedido el permiso.
  pending,

  /// El permiso está concedido.
  granted,

  /// El permiso se denegó, pero se puede volver a pedir.
  denied,

  /// El permiso está bloqueado: solo se puede cambiar en Ajustes.
  blocked,

  /// No se pudo consultar (por ejemplo, la app corre en otro sistema).
  unknown,
}

/// Consulta el estado del permiso de cámara.
///
/// **No pide el permiso**: eso lo hace el plugin `mobile_scanner`, que ya lo
/// gestiona. Aquí solo se *consulta* para distinguir los casos y poder
/// ofrecer "Abrir Ajustes" cuando el permiso está bloqueado.
class CameraPermissionService {
  const CameraPermissionService();

  static const MethodChannel _channel =
      MethodChannel('com.mercamigo/permisos');

  /// Estado actual del permiso.
  Future<CameraPermissionStatus> status() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return CameraPermissionStatus.unknown;
    }
    try {
      final String? raw = await _channel.invokeMethod<String>('cameraPermission');
      switch (raw) {
        case 'granted':
          return CameraPermissionStatus.granted;
        case 'denied':
          return CameraPermissionStatus.denied;
        case 'blocked':
          return CameraPermissionStatus.blocked;
        default:
          return CameraPermissionStatus.unknown;
      }
    } on PlatformException {
      return CameraPermissionStatus.unknown;
    } on MissingPluginException {
      return CameraPermissionStatus.unknown;
    }
  }

  /// Abre los ajustes de la app para que el usuario cambie el permiso.
  ///
  /// Devuelve `true` si se pudo abrir.
  Future<bool> openSettings() async {
    try {
      await _channel.invokeMethod<bool>('openAppSettings');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Pide el permiso de cámara (si hace falta) y devuelve el resultado.
  ///
  /// Se usa para tomar la foto del producto desde la cámara del teléfono.
  Future<CameraPermissionStatus> request() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return CameraPermissionStatus.unknown;
    }
    try {
      final String? raw =
          await _channel.invokeMethod<String>('requestCameraPermission');
      switch (raw) {
        case 'granted':
          return CameraPermissionStatus.granted;
        case 'denied':
          return CameraPermissionStatus.denied;
        default:
          return CameraPermissionStatus.unknown;
      }
    } on PlatformException {
      return CameraPermissionStatus.unknown;
    } on MissingPluginException {
      return CameraPermissionStatus.unknown;
    }
  }
}
