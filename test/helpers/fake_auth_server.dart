import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Servidor de autenticación falso para las pruebas.
///
/// Sustituye al servidor de Supabase: **no se envían correos reales ni se
/// cambian contraseñas reales**. Registra las peticiones para poder
/// comprobar qué se pidió (por ejemplo, que la verificación use el tipo
/// `recovery`).
class FakeAuthServer extends http.BaseClient {
  FakeAuthServer({
    this.recoverStatus = 200,
    this.recoverMessage = '',
    this.verifyStatus = 200,
    this.verifyMessage = '',
    this.signOutStatus = 200,
    this.userId = '11111111-1111-4111-8111-111111111111',
    this.email = 'comprador@ejemplo.com',
  });

  final int recoverStatus;
  final String recoverMessage;
  final int verifyStatus;
  final String verifyMessage;
  final int signOutStatus;
  final String userId;
  final String email;

  int recoverCalls = 0;
  int verifyCalls = 0;
  int updateUserCalls = 0;
  int signOutCalls = 0;
  String? lastRecoverEmail;
  Map<String, dynamic>? lastVerifyBody;
  Map<String, dynamic>? lastUpdateUserBody;

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
      return _response(200, '', session: session(), request: request);
    }

    if (path.endsWith('/logout')) {
      signOutCalls++;
      return _response(signOutStatus, '', request: request);
    }

    if (path.endsWith('/user')) {
      // GET /user (datos de la sesión) y PUT /user (cambio de contraseña).
      // Supabase devuelve el usuario directamente, sin envolverlo.
      if (request.method == 'put') {
        updateUserCalls++;
        lastUpdateUserBody = body;
      }
      return _response(200, '', user: user(), request: request);
    }

    if (path.contains('/token')) {
      // Inicio de sesión con correo y contraseña.
      return _response(200, '', session: session(), request: request);
    }

    return _response(200, '', request: request);
  }

  /// Usuario de la sesión.
  Map<String, dynamic> user() => <String, dynamic>{
        'id': userId,
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': email,
        'email_confirmed_at': '2026-01-01T00:00:00Z',
        'app_metadata': <String, dynamic>{'provider': 'email'},
        'user_metadata': <String, dynamic>{'nombre': 'Comprador'},
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      };

  /// Sesión de prueba.
  Map<String, dynamic> session() => <String, dynamic>{
        'access_token': jwt(),
        'token_type': 'bearer',
        'expires_in': 3600,
        'refresh_token': 'refresh-de-prueba',
        'user': user(),
      };

  /// JWT de prueba (solo se decodifica, no se valida).
  String jwt() {
    String part(Map<String, dynamic> data) =>
        base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
    final String header = part(<String, dynamic>{'alg': 'HS256', 'typ': 'JWT'});
    final String payload = part(<String, dynamic>{
      'sub': userId,
      'email': email,
      'aud': 'authenticated',
      'role': 'authenticated',
      'iat': 1767225600,
      'exp': 4102444800,
    });
    final String signature = part(<String, dynamic>{'sig': 'prueba'});
    return '$header.$payload.$signature';
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
    // `user` es el usuario directamente (así lo devuelve Supabase).
    if (user != null) body.addAll(user);
    final String encoded = jsonEncode(body);
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(encoded)),
      status,
      headers: <String, String>{'content-type': 'application/json'},
      request: request,
    );
  }
}

/// Cliente de Supabase que habla con el servidor falso.
///
/// El refresco automático se desactiva: su temporizador molesta en las
/// pruebas de widgets (en la app sí está activo).
SupabaseClient clientFor(FakeAuthServer server) {
  return SupabaseClient(
    'https://ejemplo.supabase.co',
    'clave-publicable-de-prueba',
    httpClient: server,
    // El flujo PKCE necesita almacenamiento local para el verificador.
    authOptions: AuthClientOptions(
      pkceAsyncStorage: MemoryStorage(),
      autoRefreshToken: false,
    ),
  );
}

/// Almacenamiento en memoria para el verificador PKCE.
class MemoryStorage implements GotrueAsyncStorage {
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
