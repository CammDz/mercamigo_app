import 'package:flutter/foundation.dart';

/// Registro de las etapas del arranque de la app.
///
/// Nunca se imprimen contraseñas, tokens de sesión, correos ni claves: solo
/// el nombre de la etapa y los mensajes de error, con los datos sensibles
/// enmascarados.
abstract final class BootLog {
  static const String _tag = 'Mercamigo/boot';

  /// Registra el avance de una etapa del arranque.
  static void stage(String message) {
    debugPrint('[$_tag] $message');
  }

  /// Registra un error conservando la traza completa.
  static void error(String message, Object error, [StackTrace? stack]) {
    debugPrint('[$_tag] ERROR $message: ${redact('$error')}');
    if (stack != null) {
      debugPrint('[$_tag] STACK $stack');
    }
  }

  /// Enmascara correos, JWT y claves de Supabase en un texto.
  static String redact(String value) {
    String out = value;
    out = out.replaceAll(
      RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'),
      '<correo>',
    );
    out = out.replaceAll(
      RegExp(r'eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+'),
      '<token>',
    );
    out = out.replaceAll(
      RegExp(r'sb_(publishable|secret)_[A-Za-z0-9_\-]+'),
      '<clave>',
    );
    return out;
  }
}
