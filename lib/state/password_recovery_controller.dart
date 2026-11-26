import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/config/app_config.dart';
import '../core/utils/app_date_time.dart';
import '../services/auth_service.dart';

/// Etapas del cambio de contraseña mediante código de recuperación.
///
/// El código se verifica **dentro de la app** (`verifyOTP` con tipo
/// `recovery`) antes de poder establecer una contraseña nueva.
enum PasswordRecoveryStage {
  /// No hay ningún cambio en curso.
  idle,

  /// Se está pidiendo el código al servidor.
  requestingCode,

  /// El código se ha solicitado (o se ha intentado).
  codeSent,

  /// Se está verificando el código introducido.
  verifyingCode,

  /// El código se ha verificado correctamente en este intento.
  codeVerified,

  /// Se está guardando la contraseña nueva.
  savingPassword,

  /// La contraseña se ha cambiado.
  done,
}

/// Controlador del flujo de cambio de contraseña por código.
///
/// El estado vive **solo en memoria**: no se guarda en el dispositivo ni en
/// el servidor. La única prueba de que el código se verificó es
/// [isCodeVerified], que solo se activa tras un `verifyOTP` correcto de este
/// mismo intento.
class PasswordRecoveryController extends ChangeNotifier {
  PasswordRecoveryController({required this.auth});

  /// Tiempo que hay que esperar entre dos envíos del código.
  static const Duration resendCooldown = Duration(seconds: 60);

  final AuthService auth;

  PasswordRecoveryStage _stage = PasswordRecoveryStage.idle;
  String? _email;
  String? _error;
  DateTime? _resendAvailableAt;
  Timer? _resendTicker;

  /// Etapa actual del flujo.
  PasswordRecoveryStage get stage => _stage;

  /// Correo al que se envía el código.
  String? get email => _email;

  /// Último error (texto ya listo para mostrar).
  String? get error => _error;

  /// `true` mientras el flujo está activo (evita que el AuthGate redirija al
  /// inicio cuando la verificación del código abre una sesión).
  bool get isFlowActive => _stage != PasswordRecoveryStage.idle;

  /// `true` si el flujo se inició con una sesión ya abierta (por ejemplo,
  /// "Mi cuenta → Cambiar contraseña").
  ///
  /// En ese caso **nunca** se cierra la sesión al pedir el código, al
  /// cancelar o al fallar: solo cuando el usuario cierre sesión o cuando la
  /// contraseña nueva se guarde.
  bool get keepsCurrentSession => _hadSessionAtStart;

  bool _hadSessionAtStart = false;

  /// `true` solo si el código se verificó correctamente en este intento.
  bool get isCodeVerified =>
      _stage == PasswordRecoveryStage.codeVerified ||
      _stage == PasswordRecoveryStage.savingPassword ||
      _stage == PasswordRecoveryStage.done;

  /// `true` mientras hay una operación en curso.
  bool get isBusy =>
      _stage == PasswordRecoveryStage.requestingCode ||
      _stage == PasswordRecoveryStage.verifyingCode ||
      _stage == PasswordRecoveryStage.savingPassword;

  /// Segundos que faltan para poder volver a pedir el código.
  int get resendSecondsLeft {
    final DateTime? until = _resendAvailableAt;
    if (until == null) return 0;
    final int left = secondsBetween(DateTime.now(), until).inSeconds;
    return left > 0 ? left : 0;
  }

  /// `true` cuando ya se puede volver a pedir el código.
  bool get canResend => resendSecondsLeft == 0 && !isBusy;

  /// Correo enmascarado para mostrarlo sin delatar la cuenta completa.
  String get maskedEmail => maskEmail(_email ?? '');

  /// Enmascara el correo: `nombre@dominio.com` -> `n****@dominio.com`.
  static String maskEmail(String email) {
    final int at = email.indexOf('@');
    if (at <= 0) return email;
    final String user = email.substring(0, at);
    final String domain = email.substring(at);
    if (user.length <= 1) return '*$domain';
    return '${user[0]}${'*' * (user.length - 1)}$domain';
  }

  /// Pide el código de recuperación al servidor.
  ///
  /// Se usa `resetPasswordForEmail` (el mecanismo de recuperación de
  /// Supabase), nunca `signInWithOtp`.
  Future<bool> requestCode(String email, {bool isResend = false}) async {
    final String target = email.trim();
    if (target.isEmpty) {
      _setError('Escribe el correo de tu cuenta.');
      return false;
    }

    _stage = PasswordRecoveryStage.requestingCode;
    _error = null;
    if (!isResend) {
      // Se apunta si había sesión: el flujo no debe cerrarla al terminar.
      _hadSessionAtStart = auth.isSignedIn;
    }
    // Mientras el flujo está en marcha, la sesión que abre la verificación
    // del código no se interpreta como un enlace de recuperación.
    auth.beginRecoveryFlow();
    notifyListeners();

    final AuthOutcome outcome = await auth.requestPasswordReset(target);

    if (_stage != PasswordRecoveryStage.requestingCode) {
      // El usuario canceló mientras se enviaba.
      return false;
    }

    if (!outcome.success) {
      // El flujo vuelve a estar disponible: el mensaje no revela si la
      // cuenta existe.
      _stage = PasswordRecoveryStage.idle;
      _error = 'No se pudo enviar el código. Revisa tu conexión e inténtalo '
          'de nuevo.';
      notifyListeners();
      return false;
    }

    _email = target;
    _stage = PasswordRecoveryStage.codeSent;
    _error = null;
    _startResendCooldown();
    notifyListeners();
    return true;
  }

  /// Verifica el código introducido.
  ///
  /// Usa `verifyOTP` con tipo `recovery` (nunca `email`).
  Future<bool> verifyCode(String code) async {
    final String token = code.trim();
    final String? target = _email;
    if (target == null || target.isEmpty) {
      _setError('Primero pide el código de recuperación.');
      return false;
    }
    if (token.length != codeLength) {
      _setError('El código tiene $codeLength dígitos.');
      return false;
    }

    _stage = PasswordRecoveryStage.verifyingCode;
    _error = null;
    notifyListeners();

    final AuthOutcome outcome =
        await auth.verifyRecoveryCode(email: target, code: token);

    if (!outcome.success) {
      _stage = PasswordRecoveryStage.codeSent;
      _error = outcome.message;
      notifyListeners();
      return false;
    }

    _stage = PasswordRecoveryStage.codeVerified;
    _error = null;
    notifyListeners();
    return true;
  }

  /// Guarda la contraseña nueva.
  ///
  /// Solo avanza si el código se verificó en este intento.
  Future<bool> setNewPassword(String password, String confirm) async {
    if (!isCodeVerified) {
      _setError('Verifica primero el código de recuperación.');
      return false;
    }
    if (password != confirm) {
      _setError('Las contraseñas no coinciden.');
      return false;
    }

    _stage = PasswordRecoveryStage.savingPassword;
    _error = null;
    notifyListeners();

    final AuthOutcome outcome = await auth.updatePassword(password);

    if (!outcome.success) {
      _stage = PasswordRecoveryStage.codeVerified;
      _error = outcome.message;
      notifyListeners();
      return false;
    }

    _stage = PasswordRecoveryStage.done;
    _error = null;
    notifyListeners();
    return true;
  }

  /// Cancela el flujo y limpia los datos temporales.
  ///
  /// No toca el carrito ni el historial remoto: solo el estado de este
  /// proceso.
  ///
  /// La sesión **no** se cierra si el flujo se inició con una sesión ya
  /// abierta (por ejemplo, "Mi cuenta → Cambiar contraseña"). Si el flujo
  /// empezó desde el login y la verificación del código dejó una sesión
  /// temporal de recuperación, esa sesión sí se limpia para que no lleve al
  /// panel principal por accidente.
  void cancel() {
    // Cancelar dos veces (botón "Cancelar" + PopScope) no debe tocar la
    // sesión: la segunda llamada ya no sabe que el flujo empezó con sesión
    // abierta y cerraría la sesión real del usuario.
    if (_stage == PasswordRecoveryStage.idle) return;

    _stopResendTicker();
    final bool hadSession = _hadSessionAtStart;
    _stage = PasswordRecoveryStage.idle;
    _email = null;
    _error = null;
    _resendAvailableAt = null;
    _hadSessionAtStart = false;
    auth.endRecoveryFlow();
    notifyListeners();

    if (!hadSession && auth.isSignedIn) {
      // Sesión temporal de recuperación: se cierra.
      unawaited(auth.signOut());
    }
  }

  /// Longitud real del código (la configurada en el panel de Supabase).
  ///
  /// Viene de [AppConfig.recoveryOtpLength]: es la única fuente de verdad
  /// (campo, límites, validación, botón y mensajes).
  static const int codeLength = AppConfig.recoveryOtpLength;

  void _setError(String message) {
    _error = message;
    // El flujo sigue disponible para reintentar.
    _stage = PasswordRecoveryStage.idle;
    notifyListeners();
  }

  void _startResendCooldown() {
    _stopResendTicker();
    _resendAvailableAt = DateTime.now().add(resendCooldown);
    _resendTicker = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (resendSecondsLeft == 0) {
        _stopResendTicker();
      }
      notifyListeners();
    });
  }

  void _stopResendTicker() {
    _resendTicker?.cancel();
    _resendTicker = null;
  }

  @override
  void dispose() {
    _stopResendTicker();
    super.dispose();
  }
}
