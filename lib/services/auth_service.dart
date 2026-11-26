import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/boot_log.dart';

/// Estado de la sesión del usuario.
///
/// Distingue con claridad tres situaciones que no deben confundirse:
/// · [signedOut]: no hay sesión (la petición usaría el rol `anon`).
/// · [authenticating]: hay una operación en curso.
/// · [signedIn]: hay un usuario autenticado de verdad (`auth.users`).
///
/// Una petición sin sesión NO es lo mismo que un usuario autenticado
/// anónimamente: en este proyecto **no** se usa el proveedor anónimo.
enum AuthStatus {
  signedOut,
  authenticating,
  signedIn,
  error,
}

/// Resultado de cerrar la sesión.
class SignOutResult {
  const SignOutResult({required this.sessionClosed, this.remoteError});

  /// `true` cuando la sesión local de Supabase está cerrada de verdad.
  final bool sessionClosed;

  /// Error de la revocación en el servidor (si la hubo).
  ///
  /// La sesión local queda cerrada igualmente: solo el refresh token puede
  /// seguir vivo en el servidor hasta que caduque.
  final String? remoteError;
}

/// Estado de la comprobación del rol.
///
/// El rol lo decide **el servidor** (`public.es_administrador()` y
/// `public.es_personal()`): la app nunca lo deduce de un formulario ni de
/// datos que el usuario pueda editar. Mientras la comprobación está en curso
/// no se habilita ninguna acción administrativa ni de caja.
enum AdminRoleStatus {
  /// Todavía no se ha comprobado (por ejemplo, recién se restauró la sesión).
  unknown,

  /// La consulta al servidor está en curso.
  checking,

  /// El servidor confirmó que la cuenta es de administrador.
  admin,

  /// El servidor confirmó que la cuenta es de personal de caja.
  staff,

  /// El servidor confirmó que la cuenta es de comprador.
  buyer,

  /// La comprobación falló: no se habilita ninguna acción privilegiada.
  failed,
}

/// Resultado de una operación de autenticación.
class AuthOutcome {
  const AuthOutcome({
    required this.success,
    this.message,
    this.requiresEmailConfirmation = false,
  });

  const AuthOutcome.success()
      : success = true,
        message = null,
        requiresEmailConfirmation = false;

  const AuthOutcome.failure(this.message)
      : success = false,
        requiresEmailConfirmation = false;

  const AuthOutcome.needsEmailConfirmation(this.message)
      : success = true,
        requiresEmailConfirmation = true;

  final bool success;
  final String? message;

  /// `true` cuando la cuenta se creó pero falta confirmar el correo.
  final bool requiresEmailConfirmation;
}

/// Consulta al servidor si la cuenta es de administrador.
///
/// En producción es la llamada a `public.es_administrador()`. Se puede
/// sustituir en las pruebas para comprobar los estados del rol sin red.
typedef AdminRoleProbe = Future<bool> Function();

/// Consulta al servidor si la cuenta es de personal de caja.
///
/// En producción es la llamada a `public.es_personal()`. Se puede sustituir
/// en las pruebas.
typedef StaffRoleProbe = Future<bool> Function();

/// Servicio de autenticación con **correo y contraseña** (Supabase Auth).
///
/// Compradores y administradores usan el mismo sistema. El registro público
/// siempre crea una cuenta de comprador: el rol de administrador solo se
/// concede desde el servidor.
class AuthService extends ChangeNotifier {
  AuthService(this._client, {this.adminRoleProbe, this.staffRoleProbe});

  final SupabaseClient? _client;

  /// Sondeo alternativo del rol (solo para pruebas).
  ///
  /// En producción es `null` y el rol se consulta con
  /// `public.es_administrador()`.
  final AdminRoleProbe? adminRoleProbe;

  /// Sondeo alternativo del rol de caja (solo para pruebas).
  final StaffRoleProbe? staffRoleProbe;

  AuthStatus _status = AuthStatus.signedOut;
  String? _errorMessage;
  bool _recoveryRequired = false;
  bool _recoveryFlowActive = false;
  AdminRoleStatus _adminRoleStatus = AdminRoleStatus.unknown;
  String? _localDisplayName;

  /// `true` cuando hay un servidor configurado.
  bool get isConfigured => _client != null;

  /// Cliente de Supabase (null si la app se compiló sin servidor).
  SupabaseClient? get client => _client;

  /// Estado actual de la sesión.
  AuthStatus get status => _status;

  /// Último mensaje de error.
  String? get errorMessage => _errorMessage;

  /// `true` cuando el usuario está autenticado de verdad.
  bool get isSignedIn =>
      _status == AuthStatus.signedIn &&
      _client?.auth.currentUser != null &&
      _client?.auth.currentSession != null;

  /// `true` cuando hay una operación en curso.
  bool get isBusy => _status == AuthStatus.authenticating;

  /// Identificador del usuario autenticado (`auth.users.id`).
  String? get userId => _client?.auth.currentUser?.id;

  /// Correo del usuario autenticado.
  String? get email => _client?.auth.currentUser?.email;

  /// `true` si el usuario tiene el rol administrador (lo decide el servidor).
  ///
  /// Solo es `true` cuando el servidor lo ha confirmado: si la comprobación
  /// falla, el usuario se queda con los permisos de comprador.
  bool get isAdmin => _adminRoleStatus == AdminRoleStatus.admin;

  /// `true` si el usuario tiene el rol de personal de caja.
  bool get isStaff => _adminRoleStatus == AdminRoleStatus.staff;

  /// `true` si el servidor confirmó cualquier rol privilegiado (admin o caja).
  bool get isPersonal => isAdmin || isStaff;

  /// Estado actual de la comprobación del rol.
  AdminRoleStatus get adminRoleStatus => _adminRoleStatus;

  /// `true` cuando el rol ya está resuelto (administrador, caja o comprador).
  bool get isAdminRoleResolved =>
      _adminRoleStatus == AdminRoleStatus.admin ||
      _adminRoleStatus == AdminRoleStatus.staff ||
      _adminRoleStatus == AdminRoleStatus.buyer;

  /// `true` cuando llegó un enlace de recuperación de contraseña y hay que
  /// establecer una nueva.
  bool get recoveryRequired => _recoveryRequired;

  /// Nombre visible del usuario.
  String get displayName {
    final String? metadataName =
        _client?.auth.currentUser?.userMetadata?['nombre'] as String?;
    return metadataName ??
        _localDisplayName ??
        (email?.split('@').first ?? 'Comprador');
  }

  /// Restaura la sesión guardada y escucha los cambios.
  ///
  /// Es una operación **local**: el cliente de supabase_flutter ya ha
  /// restaurado la sesión persistida al inicializarse. Aquí no se hace
  /// ninguna llamada de red, para que el arranque no dependa de Internet.
  Future<void> restoreSession() async {
    final SupabaseClient? client = _client;
    if (client == null) {
      _status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }

    client.auth.onAuthStateChange.listen(_onAuthStateChange);

    // La sesion persistida ya la restaura el cliente de supabase_flutter
    // (supabase_flutter la guarda en el almacenamiento local del
    // dispositivo); aqui solo se comprueba el estado actual.
    final bool signedIn =
        client.auth.currentSession != null && client.auth.currentUser != null;
    _status = signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;
    notifyListeners();

    // El rol de administrador se consulta despues, sin bloquear el arranque:
    // si la red falla, la app sigue funcionando como comprador.
    if (signedIn) unawaited(refreshAdminFlag());
  }

  void _onAuthStateChange(AuthState state) {
    final String event = state.event.name;
    if (event == AuthChangeEvent.passwordRecovery.name) {
      // Si el evento viene de **nuestra** verificación del código, la
      // sesión de recuperación es la del flujo que ya está en marcha: no se
      // pide otro código ni se reinicia nada.
      if (!_recoveryFlowActive) {
        _recoveryRequired = true;
      }
      _status = AuthStatus.signedIn;
      notifyListeners();
      return;
    }
    if (event == AuthChangeEvent.signedOut.name) {
      _adminRoleStatus = AdminRoleStatus.unknown;
      _recoveryRequired = false;
      _status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }
    if (event == AuthChangeEvent.signedIn.name ||
        event == AuthChangeEvent.tokenRefreshed.name ||
        event == AuthChangeEvent.userUpdated.name) {
      _status = AuthStatus.signedIn;
      notifyListeners();
    }
  }

  /// Crea una cuenta de comprador.
  ///
  /// El proyecto tiene `mailer_autoconfirm = false`: tras el registro hay
  /// que confirmar el correo, así que hasta entonces NO hay sesión y el
  /// usuario no se presenta como autenticado.
  Future<AuthOutcome> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final SupabaseClient? client = _client;
    if (client == null) {
      return const AuthOutcome.failure(
        'El servidor no está configurado en esta compilación.',
      );
    }

    _status = AuthStatus.authenticating;
    _errorMessage = null;
    notifyListeners();

    try {
      final AuthResponse response = await client.auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: redirectUri,
        data: <String, dynamic>{'nombre': name.trim()},
      );

      final bool hasSession = response.session != null;
      if (hasSession) {
        _status = AuthStatus.signedIn;
        await refreshAdminFlag();
      } else {
        _status = AuthStatus.signedOut;
      }
      notifyListeners();

      if (hasSession) return const AuthOutcome.success();
      return AuthOutcome.needsEmailConfirmation(
        'Revisa tu correo: enviamos un enlace para confirmar la cuenta. '
        'Podrás entrar después de confirmarlo.',
      );
    } on AuthException catch (error) {
      _status = AuthStatus.error;
      _errorMessage = error.message;
      notifyListeners();
      return AuthOutcome.failure(_friendlyMessage(error));
    } catch (error) {
      _status = AuthStatus.error;
      _errorMessage = '$error';
      notifyListeners();
      return AuthOutcome.failure('No se pudo crear la cuenta: $error');
    }
  }

  /// Inicia sesión con correo y contraseña.
  Future<AuthOutcome> signIn({
    required String email,
    required String password,
  }) async {
    final SupabaseClient? client = _client;
    if (client == null) {
      return const AuthOutcome.failure(
        'El servidor no está configurado en esta compilación.',
      );
    }

    _status = AuthStatus.authenticating;
    _errorMessage = null;
    notifyListeners();

    try {
      await client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      _status = AuthStatus.signedIn;
      notifyListeners();
      await refreshAdminFlag();
      return const AuthOutcome.success();
    } on AuthException catch (error) {
      _status = AuthStatus.signedOut;
      _errorMessage = error.message;
      notifyListeners();
      return AuthOutcome.failure(_friendlyMessage(error));
    } catch (error) {
      _status = AuthStatus.error;
      _errorMessage = '$error';
      notifyListeners();
      return AuthOutcome.failure('No se pudo iniciar sesión: $error');
    }
  }

  /// Verifica el código de recuperación enviado por correo.
  ///
  /// Se usa `verifyOTP` con tipo **`recovery`** (nunca `email`): es el tipo
  /// que corresponde a un código enviado con `resetPasswordForEmail`.
  ///
  /// La verificación **abre una sesión** de recuperación: por eso quien llama
  /// a este método debe seguir el flujo hasta cambiar la contraseña.
  Future<AuthOutcome> verifyRecoveryCode({
    required String email,
    required String code,
  }) async {
    final SupabaseClient? client = _client;
    if (client == null) {
      return const AuthOutcome.failure(
        'El servidor no está configurado en esta compilación.',
      );
    }

    final String token = code.trim();
    if (token.isEmpty) {
      return const AuthOutcome.failure('Escribe el código que recibiste.');
    }

    try {
      await client.auth.verifyOTP(
        email: email.trim(),
        token: token,
        type: OtpType.recovery,
      );
      return const AuthOutcome.success();
    } on AuthException catch (error) {
      return AuthOutcome.failure(_recoveryMessage(error));
    } catch (error) {
      return AuthOutcome.failure('No se pudo verificar el código: $error');
    }
  }

  /// Traduce los errores de la verificación del código.
  String _recoveryMessage(AuthException error) {
    final String message = error.message.toLowerCase();
    if (message.contains('expired')) {
      return 'El código ya caducó. Pide uno nuevo.';
    }
    if (message.contains('token_expired')) {
      return 'El código ya caducó. Pide uno nuevo.';
    }
    if (message.contains('invalid')) {
      return 'El código no es correcto. Revísalo e inténtalo de nuevo.';
    }
    if (message.contains('too many') || message.contains('rate limit')) {
      return 'Has pedido demasiados códigos. Espera un momento.';
    }
    if (message.contains('email not confirmed')) {
      return 'La cuenta todavía no está confirmada. Revisa tu correo.';
    }
    if (message.contains('signups not allowed')) {
      return 'Este correo no tiene una cuenta en Mercamigo.';
    }
    return 'No se pudo verificar el código. Inténtalo de nuevo.';
  }

  /// Envía un correo de recuperación de contraseña.
  Future<AuthOutcome> requestPasswordReset(String email) async {
    final SupabaseClient? client = _client;
    if (client == null) {
      return const AuthOutcome.failure(
        'El servidor no está configurado en esta compilación.',
      );
    }

    _status = AuthStatus.authenticating;
    notifyListeners();
    try {
      await client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: redirectUri,
      );
      // Pedir el código **no** cierra la sesión: si el usuario ya estaba
      // autenticado (por ejemplo, "Mi cuenta → Cambiar contraseña"), sigue
      // autenticado y con su rol. Solo se recupera el estado anterior.
      _status = _client?.auth.currentSession != null
          ? AuthStatus.signedIn
          : AuthStatus.signedOut;
      notifyListeners();
      return const AuthOutcome.success();
    } on AuthException catch (error) {
      _status = _client?.auth.currentSession != null
          ? AuthStatus.signedIn
          : AuthStatus.error;
      notifyListeners();
      return AuthOutcome.failure(_friendlyMessage(error));
    } catch (error) {
      _status = _client?.auth.currentSession != null
          ? AuthStatus.signedIn
          : AuthStatus.error;
      notifyListeners();
      return AuthOutcome.failure('No se pudo enviar el correo: $error');
    }
  }

  /// Establece una nueva contraseña (tras un enlace de recuperación o desde
  /// "Mi cuenta" con la sesión activa).
  Future<AuthOutcome> updatePassword(String newPassword) async {
    final SupabaseClient? client = _client;
    if (client == null) {
      return const AuthOutcome.failure(
        'El servidor no está configurado en esta compilación.',
      );
    }

    _status = AuthStatus.authenticating;
    notifyListeners();
    try {
      await client.auth.updateUser(UserAttributes(password: newPassword));
      _recoveryRequired = false;
      _status = AuthStatus.signedIn;
      notifyListeners();
      return const AuthOutcome.success();
    } on AuthException catch (error) {
      _status = AuthStatus.error;
      notifyListeners();
      return AuthOutcome.failure(_friendlyMessage(error));
    } catch (error) {
      _status = AuthStatus.error;
      notifyListeners();
      return AuthOutcome.failure('No se pudo cambiar la contraseña: $error');
    }
  }



  /// Cierra sesión en el servidor y en el dispositivo.
  ///
  /// El cierre **local** de Supabase se hace siempre (la biblioteca borra la
  /// sesión antes de llamar al servidor) y la revocación del refresh token
  /// en el servidor es un extra: si esa llamada falla (sin red, 429, 500...)
  /// la sesión local sigue cerrada y se informa del problema.
  ///
  /// Nunca deja el estado a medias: o la sesión queda cerrada, o se informa
  /// del fallo para poder reintentar.
  Future<SignOutResult> signOut() async {
    final SupabaseClient? client = _client;
    String? remoteError;

    // El estado local se cierra **de inmediato**: la app no espera a la red
    // para volver al login. La revocacion del token sigue en segundo plano.
    closeLocalSession();

    if (client != null) {
      try {
        // `global` revoca también el refresh token en el servidor.
        await client.auth.signOut(scope: SignOutScope.global);
      } catch (error) {
        remoteError = '$error';
        try {
          // Segundo intento: solo en este dispositivo.
          await client.auth.signOut(scope: SignOutScope.local);
        } catch (_) {
          // La biblioteca ya quitó la sesión local antes de la llamada de
          // red, así que el estado local está limpio.
        }
      }
    }

    final bool closed = client == null || client.auth.currentSession == null;
    return SignOutResult(
      sessionClosed: closed,
      remoteError: remoteError,
    );
  }

  /// Cierra la sesion local **sin tocar la red**.
  ///
  /// La pantalla de login aparece al instante; la revocacion del token en el
  /// servidor se puede hacer despues (ver [signOut]).
  void closeLocalSession() {
    _adminRoleStatus = AdminRoleStatus.unknown;
    _recoveryRequired = false;
    _recoveryFlowActive = false;
    _localDisplayName = null;
    _status = AuthStatus.signedOut;
    notifyListeners();
  }

  /// Deja la sesión iniciada con un token concreto.
  ///
  /// **Solo para pruebas**: el servidor de Supabase se sustituye por un
  /// cliente HTTP falso, así que no hay red ni cuenta real.
  @visibleForTesting
  Future<void> signInForTest(
    SupabaseClient client,
    String accessToken,
  ) async {
    await client.auth.setSession('refresh-de-prueba', accessToken: accessToken);
    _status = AuthStatus.signedIn;
    notifyListeners();
  }

  /// Marca que seHa pedido un enlace de recuperación (para navegar a la
  /// pantalla de nueva contraseña).
  void acknowledgeRecovery() {
    _recoveryRequired = false;
    notifyListeners();
  }

  /// Marca que hay un flujo de recuperación con código en marcha.
  ///
  /// Mientras está activo, la sesión que abre `verifyOTP` **no** se
  /// interpreta como un enlace de recuperación: es la del propio flujo, así
  /// que no se pide otro código ni se reinicia la navegación.
  void beginRecoveryFlow() {
    _recoveryFlowActive = true;
  }

  /// Marca que el flujo de recuperación con código ha terminado.
  void endRecoveryFlow() {
    _recoveryFlowActive = false;
  }

  /// `true` mientras hay un flujo de recuperación con código en marcha.
  bool get isRecoveryFlowActive => _recoveryFlowActive;

  /// Consulta al servidor si el usuario es administrador o personal de caja.
  ///
  /// Nunca bloquea el arranque: tiene tiempo límite y, si falla, el usuario
  /// se queda con los permisos de comprador (nunca con los privilegiados).
  Future<void> refreshAdminFlag() async {
    if (_client == null && adminRoleProbe == null) {
      _adminRoleStatus = AdminRoleStatus.unknown;
      notifyListeners();
      return;
    }

    // Durante la comprobación la interfaz muestra un estado de verificación
    // y no habilita ninguna acción administrativa.
    _adminRoleStatus = AdminRoleStatus.checking;
    notifyListeners();

    try {
      final bool admin = await (adminRoleProbe ?? _defaultAdminRoleProbe)();
      if (admin) {
        _adminRoleStatus = AdminRoleStatus.admin;
      } else {
        final bool staff = await (staffRoleProbe ?? _defaultStaffRoleProbe)();
        _adminRoleStatus =
            staff ? AdminRoleStatus.staff : AdminRoleStatus.buyer;
      }
    } catch (error, stack) {
      BootLog.error('No se pudo consultar el rol de la cuenta', error, stack);
      // Si la comprobación falla NO se habilitan acciones privilegiadas.
      _adminRoleStatus = AdminRoleStatus.failed;
    }
    notifyListeners();
  }

  /// Sondeo por defecto: pregunta al servidor si la sesión es de admin.
  Future<bool> _defaultAdminRoleProbe() async {
    final SupabaseClient? client = _client;
    if (client == null || !isSignedIn) return false;
    final Object? result =
        await client.rpc('es_administrador').timeout(const Duration(seconds: 10));
    return result == true;
  }

  /// Sondeo por defecto: pregunta al servidor si la sesión es de caja.
  Future<bool> _defaultStaffRoleProbe() async {
    final SupabaseClient? client = _client;
    if (client == null || !isSignedIn) return false;
    final Object? result =
        await client.rpc('es_personal').timeout(const Duration(seconds: 10));
    return result == true;
  }

  /// Guarda un nombre local (modo sin cuenta).
  void setLocalDisplayName(String name) {
    _localDisplayName = name;
    notifyListeners();
  }

  /// Mensajes de error legibles para el usuario.
  String _friendlyMessage(AuthException error) {
    final String message = error.message.toLowerCase();
    if (message.contains('invalid login credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (message.contains('email not confirmed')) {
      return 'La cuenta todavía no está confirmada. Revisa tu correo.';
    }
    if (message.contains('user already registered')) {
      return 'Ya existe una cuenta con ese correo.';
    }
    if (message.contains('password should be at least')) {
      return 'La contraseña debe tener al menos 6 caracteres.';
    }
    if (message.contains('unable to validate email')) {
      return 'El correo no tiene un formato válido.';
    }
    if (message.contains('rate limit')) {
      return 'Demasiados intentos. Espera un momento e inténtalo de nuevo.';
    }
    return error.message;
  }

  /// Enlace de retorno a la app (confirmación y recuperación).
  ///
  /// Debe estar registrado en el manifiesto de Android y en las URL de
  /// redireccion permitidas del proyecto Supabase.
  static const String redirectUri = 'mercamigo://auth/callback';
}
