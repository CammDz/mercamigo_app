import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercamigo_app/services/auth_service.dart';
import 'package:mercamigo_app/ui/screens/admin_panel_screen.dart';
import 'package:mercamigo_app/ui/screens/auth_gate.dart';
import 'package:mercamigo_app/ui/screens/home_screen.dart';
import 'package:mercamigo_app/ui/screens/staff_home_screen.dart';
import 'package:provider/provider.dart';

void main() {
  group('Estado del rol de administrador', () {
    test('Empieza sin comprobar: no se habilita ninguna acción administrativa',
        () async {
      final AuthService auth = AuthService(null);
      expect(auth.adminRoleStatus, AdminRoleStatus.unknown);
      expect(auth.isAdmin, isFalse);
    });

    test('El servidor confirma que la cuenta es de administrador', () async {
      final AuthService auth =
          AuthService(null, adminRoleProbe: () async => true);
      await auth.refreshAdminFlag();
      expect(auth.adminRoleStatus, AdminRoleStatus.admin);
      expect(auth.isAdmin, isTrue);
    });

    test('El servidor confirma que la cuenta es de comprador', () async {
      final AuthService auth =
          AuthService(null, adminRoleProbe: () async => false);
      await auth.refreshAdminFlag();
      expect(auth.adminRoleStatus, AdminRoleStatus.buyer);
      expect(auth.isAdmin, isFalse);
      expect(auth.isStaff, isFalse);
    });

    test('El servidor confirma que la cuenta es de personal de caja', () async {
      final AuthService auth = AuthService(
        null,
        adminRoleProbe: () async => false,
        staffRoleProbe: () async => true,
      );
      await auth.refreshAdminFlag();
      expect(auth.adminRoleStatus, AdminRoleStatus.staff);
      expect(auth.isStaff, isTrue);
      expect(auth.isPersonal, isTrue);
      expect(auth.isAdmin, isFalse);
    });

    test('El administrador no depende del sondeo de caja', () async {
      final AuthService auth = AuthService(
        null,
        adminRoleProbe: () async => true,
        staffRoleProbe: () async => true,
      );
      await auth.refreshAdminFlag();
      expect(auth.adminRoleStatus, AdminRoleStatus.admin);
      expect(auth.isAdmin, isTrue);
    });

    test('Si la comprobación falla NO se habilita el rol de administrador',
        () async {
      final AuthService auth = AuthService(
        null,
        adminRoleProbe: () async => throw Exception('sin red'),
      );
      await auth.refreshAdminFlag();
      expect(auth.adminRoleStatus, AdminRoleStatus.failed);
      expect(auth.isAdmin, isFalse);
    });

    test('Cerrar sesión elimina el estado administrativo de la interfaz',
        () async {
      final AuthService auth =
          AuthService(null, adminRoleProbe: () async => true);
      await auth.refreshAdminFlag();
      expect(auth.isAdmin, isTrue);

      await auth.signOut();

      expect(auth.isAdmin, isFalse);
      expect(auth.adminRoleStatus, AdminRoleStatus.unknown);
    });
  });

  group('Pantalla según el rol', () {
    test('El administrador entra al panel administrativo, no al inicio de compra',
        () {
      expect(
        homeForRole(AdminRoleStatus.admin),
        isA<AdminPanelScreen>(),
      );
    });

    test('El comprador entra al inicio de compra', () {
      expect(homeForRole(AdminRoleStatus.buyer), isA<HomeScreen>());
    });

    test('El personal de caja entra a la interfaz de caja', () {
      expect(homeForRole(AdminRoleStatus.staff), isA<StaffHomeScreen>());
    });

    test('Mientras se comprueba el rol NO se muestra una pantalla intermedia',
        () {
      // La app entra directamente en la experiencia de compra: no hay ninguna
      // pantalla de "verificando permisos".
      expect(homeForRole(AdminRoleStatus.checking), isA<HomeScreen>());
      expect(homeForRole(AdminRoleStatus.unknown), isA<HomeScreen>());
    });

    test('Si la comprobación falla se entra como comprador', () {
      expect(homeForRole(AdminRoleStatus.failed), isA<HomeScreen>());
    });
  });

  group('El panel administrativo no se abre a un comprador', () {
    testWidgets('Un comprador no ve las secciones administrativas',
        (WidgetTester tester) async {
      final AuthService auth =
          AuthService(null, adminRoleProbe: () async => false);
      await auth.refreshAdminFlag();

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthService>.value(
          value: auth,
          child: const MaterialApp(home: AdminPanelScreen()),
        ),
      );
      await tester.pump();

      // Sin rol no se ven las secciones de administración...
      expect(find.text('Productos'), findsNothing);
      expect(find.text('Tienda'), findsNothing);
      expect(find.text('Cerrar sesión'), findsNothing);

      // ...y se explica por qué.
      expect(
        find.textContaining('no tiene el rol de administrador'),
        findsOneWidget,
      );
    });

    testWidgets('El administrador ve el panel con sus accesos',
        (WidgetTester tester) async {
      final AuthService auth =
          AuthService(null, adminRoleProbe: () async => true);
      await auth.refreshAdminFlag();

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthService>.value(
          value: auth,
          child: const MaterialApp(home: AdminPanelScreen()),
        ),
      );
      await tester.pump();

      expect(find.byType(AdminPanelScreen), findsOneWidget);
      expect(find.text('Productos'), findsOneWidget);
      expect(find.text('Tienda'), findsOneWidget);
      expect(find.text('Personal de caja'), findsOneWidget);
      expect(find.text('Mi cuenta'), findsOneWidget);
      expect(find.text('Cerrar sesión'), findsOneWidget);
    });
  });
}
