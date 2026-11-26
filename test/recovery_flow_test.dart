import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercamigo_app/core/config/app_config.dart';
import 'package:mercamigo_app/services/auth_service.dart';
import 'package:mercamigo_app/state/password_recovery_controller.dart';
import 'package:mercamigo_app/ui/screens/enter_recovery_code_screen.dart';
import 'package:mercamigo_app/ui/screens/reset_password_screen.dart';
import 'package:mercamigo_app/ui/widgets/primary_button.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/fake_auth_server.dart';

/// Pruebas del flujo de recuperación por código y del cierre de sesión.
///
/// Todo es **simulado**: el servidor de Supabase se sustituye por un cliente
/// HTTP falso. No se envían correos reales, no se cambian contraseñas reales
/// y no se cierran sesiones reales.
void main() {
  const String email = 'comprador@ejemplo.com';

  group('Longitud del código', () {
    test('La longitud viene de la configuración y es de 8 dígitos', () {
      expect(AppConfig.recoveryOtpLength, 8);
      expect(
        PasswordRecoveryController.codeLength,
        AppConfig.recoveryOtpLength,
      );
    });

    test('Un código de 8 dígitos se verifica', () async {
      final FakeAuthServer server = FakeAuthServer();
      final AuthService auth = AuthService(clientFor(server));
      final PasswordRecoveryController controller = _controllerFor(auth);
      await controller.requestCode(email);

      final bool ok = await controller.verifyCode('12345678');

      expect(ok, isTrue);
      expect(server.lastVerifyBody?['token'], '12345678');
    });

    test('Un código con cero inicial se conserva tal cual', () async {
      final FakeAuthServer server = FakeAuthServer();
      final AuthService auth = AuthService(clientFor(server));
      final PasswordRecoveryController controller = _controllerFor(auth);
      await controller.requestCode(email);

      await controller.verifyCode('00012345');

      expect(server.lastVerifyBody?['token'], '00012345');
    });

    test('Un código incompleto no se verifica', () async {
      final FakeAuthServer server = FakeAuthServer();
      final AuthService auth = AuthService(clientFor(server));
      final PasswordRecoveryController controller = _controllerFor(auth);
      await controller.requestCode(email);

      // 7 dígitos: falta uno.
      expect(await controller.verifyCode('1234567'), isFalse);
      expect(await controller.verifyCode('123'), isFalse);
      expect(server.verifyCalls, 0);
    });

    test('Un código incorrecto o vencido se rechaza', () async {
      final FakeAuthServer server = FakeAuthServer(
        verifyStatus: 403,
        verifyMessage: 'Token has expired or is invalid',
      );
      final AuthService auth = AuthService(clientFor(server));
      final PasswordRecoveryController controller = _controllerFor(auth);
      await controller.requestCode(email);

      expect(await controller.verifyCode('99999999'), isFalse);
      expect(controller.isCodeVerified, isFalse);
      expect(controller.error, isNotNull);
    });
  });

  group('Entrada del código', () {
    testWidgets('Se pueden pegar los 8 dígitos completos con espacios', (
      WidgetTester tester,
    ) async {
      final FakeAuthServer server = FakeAuthServer();
      final AuthService auth = AuthService(clientFor(server));
      final PasswordRecoveryController controller = _controllerFor(auth);
      await controller.requestCode(email);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<PasswordRecoveryController>.value(
            value: controller,
            child: const EnterRecoveryCodeScreen(),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, '0123 4567');
      await tester.pumpAndSettle();

      // El campo queda con los 8 dígitos (los espacios se eliminan).
      final TextField field = tester.widget<TextField>(
        find.byType(TextField).first,
      );
      expect(field.controller?.text, '01234567');
      controller.cancel();
    });

    testWidgets('El botón de verificar solo se habilita con la longitud '
        'completa', (WidgetTester tester) async {
      final FakeAuthServer server = FakeAuthServer();
      final AuthService auth = AuthService(clientFor(server));
      final PasswordRecoveryController controller = _controllerFor(auth);
      await controller.requestCode(email);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<PasswordRecoveryController>.value(
            value: controller,
            child: const EnterRecoveryCodeScreen(),
          ),
        ),
      );
      await tester.pump();

      InkWell state() => tester.widget<InkWell>(
        find.descendant(
          of: find.byType(PrimaryButton).first,
          matching: find.byType(InkWell),
        ),
      );

      // Con 7 dígitos no se puede verificar.
      await tester.enterText(find.byType(TextField).first, '1234567');
      await tester.pumpAndSettle();
      expect(state().onTap, isNull);

      // Con los 8 dígitos, sí.
      await tester.enterText(find.byType(TextField).first, '12345678');
      await tester.pumpAndSettle();
      expect(state().onTap, isNotNull);
      controller.cancel();
    });

    testWidgets('Un código incorrecto no lleva a la nueva contraseña', (
      WidgetTester tester,
    ) async {
      final FakeAuthServer server = FakeAuthServer(
        verifyStatus: 403,
        verifyMessage: 'Token has expired or is invalid',
      );
      final AuthService auth = AuthService(clientFor(server));
      final PasswordRecoveryController controller = _controllerFor(auth);
      await controller.requestCode(email);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<PasswordRecoveryController>.value(
            value: controller,
            child: const EnterRecoveryCodeScreen(),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, '99999999');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verificar código'));
      await tester.pumpAndSettle();

      // No se ha navegado a la nueva contraseña.
      expect(find.byType(ResetPasswordScreen), findsNothing);
      expect(controller.isCodeVerified, isFalse);
      controller.cancel();
    });
  });

  group('La sesión no se cierra al pedir el código', () {
    test('Pedir el código con la sesión abierta la conserva', () async {
      final FakeAuthServer server = FakeAuthServer();
      final SupabaseClient client = clientFor(server);
      final AuthService auth = AuthService(client);
      await auth.signInForTest(client, server.jwt());
      expect(auth.isSignedIn, isTrue);

      final PasswordRecoveryController controller = _controllerFor(auth);
      await controller.requestCode(email);

      expect(auth.isSignedIn, isTrue);
      expect(controller.keepsCurrentSession, isTrue);
    });

    test('Cancelar con la sesión abierta la conserva', () async {
      final FakeAuthServer server = FakeAuthServer();
      final SupabaseClient client = clientFor(server);
      final AuthService auth = AuthService(client);
      await auth.signInForTest(client, server.jwt());
      final PasswordRecoveryController controller = _controllerFor(auth);
      await controller.requestCode(email);

      controller.cancel();

      // La sesión sigue viva: pedir el código no cierra sesión.
      expect(auth.isSignedIn, isTrue);
    });

    test('Cancelar desde el login cierra la sesión temporal', () async {
      final FakeAuthServer server = FakeAuthServer();
      final SupabaseClient client = clientFor(server);
      final AuthService auth = AuthService(client);
      final PasswordRecoveryController controller = _controllerFor(auth);

      // Sin sesión previa: el flujo empieza desde el login.
      await controller.requestCode(email);
      // La verificación del código deja una sesión de recuperación.
      await auth.signInForTest(client, server.jwt());
      expect(auth.isSignedIn, isTrue);

      controller.cancel();

      // Esa sesión temporal se limpia: no puede llevar al panel principal.
      expect(auth.isSignedIn, isFalse);
    });
  });

  group('Cierre de sesión', () {
    test('Cierra la sesión local de verdad', () async {
      final FakeAuthServer server = FakeAuthServer();
      final SupabaseClient client = clientFor(server);
      final AuthService auth = AuthService(client);
      await auth.signInForTest(client, server.jwt());
      expect(auth.isSignedIn, isTrue);

      final SignOutResult result = await auth.signOut();

      expect(result.sessionClosed, isTrue);
      expect(auth.isSignedIn, isFalse);
      expect(server.signOutCalls, greaterThan(0));
    });

    test('Si el servidor falla, la sesión local sigue cerrada', () async {
      final FakeAuthServer server = FakeAuthServer(signOutStatus: 500);
      final SupabaseClient client = clientFor(server);
      final AuthService auth = AuthService(client);
      await auth.signInForTest(client, server.jwt());

      final SignOutResult result = await auth.signOut();

      // La sesión local está cerrada aunque la revocación remota falle.
      expect(auth.isSignedIn, isFalse);
      expect(result.remoteError, isNotNull);
    });
  });

  group('Cancelar el cambio de contraseña', () {
    test('Cancelar dos veces no cierra la sesión abierta', () async {
      final _SignedInAuth auth = _SignedInAuth();
      final PasswordRecoveryController controller = _controllerFor(auth);

      await controller.requestCode(email);
      expect(controller.stage, PasswordRecoveryStage.codeSent);

      // El botón "Cancelar" llama a cancel() y el PopScope vuelve a llamarlo.
      controller.cancel();
      controller.cancel();

      expect(auth.signOutCalls, 0);
      expect(auth.isSignedIn, isTrue);
      expect(controller.stage, PasswordRecoveryStage.idle);
    });
  });
}

/// Servicio simulado con una sesión ya abierta.
///
/// Sirve para comprobar que cancelar el cambio de contraseña desde "Mi
/// cuenta" no cierra la sesión del comprador, ni siquiera si la pantalla
/// cancela dos veces.
class _SignedInAuth extends AuthService {
  _SignedInAuth() : super(null);

  int signOutCalls = 0;

  @override
  bool get isSignedIn => true;

  @override
  Future<AuthOutcome> requestPasswordReset(String email) async =>
      const AuthOutcome.success();

  @override
  void beginRecoveryFlow() {}

  @override
  void endRecoveryFlow() {}

  @override
  Future<SignOutResult> signOut() async {
    signOutCalls++;
    return const SignOutResult(sessionClosed: true);
  }
}

/// Crea un controlador y lo cierra al terminar la prueba.
PasswordRecoveryController _controllerFor(AuthService auth) {
  final PasswordRecoveryController controller = PasswordRecoveryController(
    auth: auth,
  );
  addTearDown(controller.dispose);
  return controller;
}
