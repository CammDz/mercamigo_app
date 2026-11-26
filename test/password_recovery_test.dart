import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mercamigo_app/services/auth_service.dart';
import 'package:mercamigo_app/state/password_recovery_controller.dart';
import 'package:mercamigo_app/ui/screens/reset_password_screen.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pruebas **simuladas** del cambio de contraseña por código.
///
/// No se envía ningún correo real ni se cambia ninguna contraseña real: el
/// servidor de Supabase se sustituye por un cliente HTTP falso que responde
/// como lo haría el panel.
void main() {
  const String email = 'comprador@ejemplo.com';

  group('Solicitud del código', () {
    test('Se pide con resetPasswordForEmail y la respuesta es genérica',
        () async {
      final _FakeAuthServer server = _FakeAuthServer();
      final AuthService auth = AuthService(_clientFor(server));
      final PasswordRecoveryController controller = _controllerFor(auth);

      final bool ok = await controller.requestCode(email);

      expect(ok, isTrue);
      expect(server.recoverCalls, 1);
      expect(server.lastRecoverEmail, email);
      expect(controller.stage, PasswordRecoveryStage.codeSent);
      // El correo se muestra enmascarado.
      expect(controller.maskedEmail, 'c********@ejemplo.com');
    });

    test('Un error del servidor no se muestra como envío correcto', () async {
      final _FakeAuthServer server =
          _FakeAuthServer(recoverStatus: 500, recoverMessage: 'smtp error');
      final AuthService auth = AuthService(_clientFor(server));
      final PasswordRecoveryController controller = _controllerFor(auth);

      final bool ok = await controller.requestCode(email);

      expect(ok, isFalse);
      expect(controller.stage, isNot(PasswordRecoveryStage.codeSent));
      expect(controller.error, isNotNull);
      // El mensaje no revela si la cuenta existe.
      expect(controller.error, isNot(contains('registrado')));
    });

    test('El límite de envíos del servidor (429) se muestra como error',
        () async {
      final _FakeAuthServer server =
          _FakeAuthServer(recoverStatus: 429, recoverMessage: 'rate limited');
      final AuthService auth = AuthService(_clientFor(server));
      final PasswordRecoveryController controller = _controllerFor(auth);

      final bool ok = await controller.requestCode(email);

      expect(ok, isFalse);
      expect(controller.error, isNotNull);
    });
  });

  group('Verificación del código', () {
    test('Se verifica con verifyOTP de tipo recovery', () async {
      final _FakeAuthServer server = _FakeAuthServer();
      final AuthService auth = AuthService(_clientFor(server));
      final PasswordRecoveryController controller = _controllerFor(auth);
      await controller.requestCode(email);

      final bool ok = await controller.verifyCode('01234567');

      expect(ok, isTrue);
      expect(server.verifyCalls, 1);
      expect(server.lastVerifyBody?['type'], 'recovery');
      expect(server.lastVerifyBody?['email'], email);
      expect(server.lastVerifyBody?['token'], '01234567');
      expect(controller.isCodeVerified, isTrue);
    });

    test('Un código con cero inicial se envía tal cual (texto)', () async {
      final _FakeAuthServer server = _FakeAuthServer();
      final AuthService auth = AuthService(_clientFor(server));
      final PasswordRecoveryController controller = _controllerFor(auth);
      await controller.requestCode(email);

      await controller.verifyCode('00012345');

      // El código se guarda como String: no pierde el cero inicial.
      expect(server.lastVerifyBody?['token'], '00012345');
      expect(controller.isCodeVerified, isTrue);
    });

    test('Un código incorrecto se rechaza y no habilita la nueva contraseña',
        () async {
      final _FakeAuthServer server = _FakeAuthServer(
        verifyStatus: 403,
        verifyMessage: 'Token has expired or is invalid',
      );
      final AuthService auth = AuthService(_clientFor(server));
      final PasswordRecoveryController controller = _controllerFor(auth);
      await controller.requestCode(email);

      final bool ok = await controller.verifyCode('99999999');

      expect(ok, isFalse);
      expect(controller.isCodeVerified, isFalse);
      expect(controller.error, isNotNull);
      // Se puede reintentar: el flujo sigue disponible.
      expect(controller.stage, PasswordRecoveryStage.codeSent);
    });

    test('Un código caducado se informa como caducado', () async {
      final _FakeAuthServer server = _FakeAuthServer(
        verifyStatus: 403,
        verifyMessage: 'Token has expired',
      );
      final AuthService auth = AuthService(_clientFor(server));
      final PasswordRecoveryController controller = _controllerFor(auth);
      await controller.requestCode(email);

      final bool ok = await controller.verifyCode('12345678');

      expect(ok, isFalse);
      expect(controller.error, contains('caduc'));
    });

    test('No se verifica con un código incompleto', () async {
      final _FakeAuthServer server = _FakeAuthServer();
      final AuthService auth = AuthService(_clientFor(server));
      final PasswordRecoveryController controller = _controllerFor(auth);
      await controller.requestCode(email);

      final bool ok = await controller.verifyCode('123');

      expect(ok, isFalse);
      expect(server.verifyCalls, 0);
    });
  });

  group('Reenvío del código', () {
    test('Hay que esperar antes de volver a pedir el código', () async {
      final _FakeAuthServer server = _FakeAuthServer();
      final AuthService auth = AuthService(_clientFor(server));
      final PasswordRecoveryController controller = _controllerFor(auth);
      await controller.requestCode(email);

      expect(controller.canResend, isFalse);
      expect(controller.resendSecondsLeft, greaterThan(0));
      expect(
        controller.resendSecondsLeft,
        lessThanOrEqualTo(
          PasswordRecoveryController.resendCooldown.inSeconds,
        ),
      );
    });
  });

  group('Nueva contraseña', () {
    test('Sin verificar el código no se puede cambiar la contraseña',
        () async {
      final _FakeAuthServer server = _FakeAuthServer();
      final AuthService auth = AuthService(_clientFor(server));
      final PasswordRecoveryController controller = _controllerFor(auth);
      await controller.requestCode(email);

      final bool ok =
          await controller.setNewPassword('nuevacontra1', 'nuevacontra1');

      expect(ok, isFalse);
      expect(controller.isCodeVerified, isFalse);
      expect(server.updateUserCalls, 0);
    });

    test('Las contraseñas deben coincidir', () async {
      final _FakeAuthServer server = _FakeAuthServer();
      final AuthService auth = AuthService(_clientFor(server));
      final PasswordRecoveryController controller = _controllerFor(auth);
      await controller.requestCode(email);
      await controller.verifyCode('12345678');

      final bool ok = await controller.setNewPassword('nuevacontra1', 'otra12345');

      expect(ok, isFalse);
      expect(controller.error, contains('coinciden'));
    });

    test('Tras verificar, la contraseña nueva se guarda', () async {
      final _FakeAuthServer server = _FakeAuthServer();
      final AuthService auth = AuthService(_clientFor(server));
      final PasswordRecoveryController controller = _controllerFor(auth);
      await controller.requestCode(email);
      await controller.verifyCode('12345678');

      final bool ok =
          await controller.setNewPassword('nuevacontra1', 'nuevacontra1');

      expect(ok, isTrue);
      expect(server.updateUserCalls, 1);
      expect(controller.stage, PasswordRecoveryStage.done);
    });
  });

  group('Cancelación y limpieza', () {
    test('Cancelar limpia los datos temporales del flujo', () async {
      final _FakeAuthServer server = _FakeAuthServer();
      final AuthService auth = AuthService(_clientFor(server));
      final PasswordRecoveryController controller = _controllerFor(auth);
      await controller.requestCode(email);
      await controller.verifyCode('12345678');

      controller.cancel();

      expect(controller.stage, PasswordRecoveryStage.idle);
      expect(controller.isFlowActive, isFalse);
      expect(controller.isCodeVerified, isFalse);
      expect(controller.email, isNull);
    });
  });

  group('La pantalla de nueva contraseña', () {
    testWidgets('Sin código verificado no deja cambiar la contraseña',
        (WidgetTester tester) async {
      final _FakeAuthServer server = _FakeAuthServer();
      final AuthService auth = AuthService(_clientFor(server));
      final PasswordRecoveryController controller = _controllerFor(auth);
      // El código no está verificado: el flujo ni siquiera ha empezado.
      await controller.requestCode(email);
      controller.cancel();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<PasswordRecoveryController>.value(
            value: controller,
            child: const ResetPasswordScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Verifica primero el código'), findsOneWidget);
      expect(find.text('Guardar contraseña'), findsNothing);
    });
  });
}

/// Crea un controlador y lo cierra al terminar la prueba (el temporizador de
/// reenvío sigue vivo si no).
PasswordRecoveryController _controllerFor(AuthService auth) {
  final PasswordRecoveryController controller =
      PasswordRecoveryController(auth: auth);
  addTearDown(controller.dispose);
  return controller;
}

/// Construye un cliente de Supabase que habla con el servidor falso.
SupabaseClient _clientFor(_FakeAuthServer server) {
  return SupabaseClient(
    'https://ejemplo.supabase.co',
    'clave-publicable-de-prueba',
    httpClient: server,
    // El flujo PKCE necesita almacenamiento local para el verificador.
    // El refresco automático se desactiva: su temporizador molesta en las
    // pruebas de widgets (en la app sí está activo).
    authOptions: AuthClientOptions(
      pkceAsyncStorage: _MemoryStorage(),
      autoRefreshToken: false,
    ),
  );
}

/// Almacenamiento en memoria para el verificador PKCE.
class _MemoryStorage implements GotrueAsyncStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => _values[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }
}

/// Sustituye al servidor de autenticación de Supabase.
class _FakeAuthServer extends http.BaseClient {
  _FakeAuthServer({
    this.recoverStatus = 200,
    this.recoverMessage = '',
    this.verifyStatus = 200,
    this.verifyMessage = '',
  });

  final int recoverStatus;
  final String recoverMessage;
  final int verifyStatus;
  final String verifyMessage;

  int recoverCalls = 0;
  int verifyCalls = 0;
  int updateUserCalls = 0;
  String? lastRecoverEmail;
  Map<String, dynamic>? lastVerifyBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final String path = request.url.path;
    final Map<String, dynamic> body =
        request is http.Request && request.body.isNotEmpty
            ? (jsonDecode(request.body) as Map<String, dynamic>)
            : <String, dynamic>{};

    if (path.endsWith('/recover')) {
      recoverCalls++;
      lastRecoverEmail = body['email'] as String?;
      return _response(recoverStatus, recoverMessage, request: request);
    }

    if (path.endsWith('/verify')) {
      verifyCalls++;
      lastVerifyBody = body;
      if (verifyStatus != 200) {
        return _response(verifyStatus, verifyMessage, request: request);
      }
      return _response(200, '', session: _session(), request: request);
    }

    if (path.endsWith('/user')) {
      // Actualización de la contraseña (PUT /user).
      updateUserCalls++;
      return _response(200, '', user: _user(), request: request);
    }

    return _response(200, '', request: request);
  }

  Map<String, dynamic> _user() => <String, dynamic>{
        'id': _userId,
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'comprador@ejemplo.com',
        'email_confirmed_at': '2026-01-01T00:00:00Z',
        'app_metadata': <String, dynamic>{'provider': 'email'},
        'user_metadata': <String, dynamic>{'nombre': 'Comprador'},
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      };

  Map<String, dynamic> _session() => <String, dynamic>{
        'access_token': _jwt(),
        'token_type': 'bearer',
        'expires_in': 3600,
        'refresh_token': 'refresh-de-prueba',
        'user': _user(),
      };

  /// JWT de prueba (solo se decodifica, no se valida).
  String _jwt() {
    String part(Map<String, dynamic> data) =>
        base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
    final String header = part(<String, dynamic>{'alg': 'HS256', 'typ': 'JWT'});
    final String payload = part(<String, dynamic>{
      'sub': _userId,
      'email': 'comprador@ejemplo.com',
      'aud': 'authenticated',
      'role': 'authenticated',
      'iat': 1767225600,
      'exp': 4102444800,
    });
    return '$header.$payload.firma';
  }

  http.StreamedResponse _response(
    int status,
    String message, {
    Map<String, dynamic>? session,
    Map<String, dynamic>? user,
    http.BaseRequest? request,
  }) {
    final Map<String, dynamic> body = <String, dynamic>{};
    if (message.isNotEmpty) {
      body['error_code'] = 'error';
      body['msg'] = message;
      body['message'] = message;
    }
    if (session != null) body.addAll(session);
    if (user != null) body['user'] = user;
    final String encoded = jsonEncode(body);
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(encoded)),
      status,
      headers: <String, String>{'content-type': 'application/json'},
      request: request,
    );
  }
}

const String _userId = '11111111-1111-4111-8111-111111111111';
