import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercamigo_app/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // El plugin de almacenamiento no existe en el entorno de test: se simula.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('Sin sesión se muestra el inicio de sesión, no una pantalla negra',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MercamigoApp());
    await tester.pump();
    // El arranque es asincrono: se da tiempo a que termine.
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(Scaffold), findsWidgets);
    expect(find.text('Iniciar sesión'), findsWidgets);
    expect(find.text('¿No tienes cuenta? Crear cuenta'), findsOneWidget);
    expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
  });

  testWidgets('El arranque termina y no se queda bloqueado',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MercamigoApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    // Ya no hay pantalla de arranque: se ha llegado a la app.
    expect(find.text('Iniciando la aplicación...'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
