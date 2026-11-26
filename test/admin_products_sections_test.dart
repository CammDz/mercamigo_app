import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercamigo_app/data/models/admin_product.dart';
import 'package:mercamigo_app/repositories/admin_catalog_repository.dart';
import 'package:mercamigo_app/ui/screens/admin_products_screen.dart';
import 'package:mercamigo_app/ui/screens/camera_diagnostic_screen.dart';
import 'package:provider/provider.dart';

/// Repositorio de administración con datos fijos (sin servidor).
class _FakeAdminRepository extends AdminCatalogRepository {
  _FakeAdminRepository() : super(client: null);

  @override
  Future<AdminCatalogSnapshot> load() async {
    return const AdminCatalogSnapshot(
      categories: <AdminCategory>[
        AdminCategory(id: 'cat-1', name: 'Bebidas', isActive: true),
      ],
      products: <AdminProduct>[
        AdminProduct(
          id: 'p1',
          name: 'Producto activo',
          description: '',
          categoryId: 'cat-1',
          categoryName: 'Bebidas',
          price: 1000,
          isActive: true,
          codes: <ProductCode>[
            ProductCode(id: 'c1', code: '770001', type: 'barras'),
          ],
        ),
        AdminProduct(
          id: 'p2',
          name: 'Otro activo',
          description: '',
          categoryId: 'cat-1',
          categoryName: 'Bebidas',
          price: 2000,
          isActive: true,
          codes: <ProductCode>[],
        ),
        AdminProduct(
          id: 'p3',
          name: 'Producto desactivado',
          description: '',
          categoryId: 'cat-1',
          categoryName: 'Bebidas',
          price: 3000,
          isActive: false,
          codes: <ProductCode>[
            ProductCode(id: 'c3', code: '770003', type: 'barras'),
          ],
        ),
      ],
    );
  }
}

void main() {
  Widget app() {
    return Provider<AdminCatalogRepository>.value(
      value: _FakeAdminRepository(),
      child: const MaterialApp(home: AdminProductsScreen()),
    );
  }

  testWidgets('Muestra las dos secciones con su número de productos', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Activos'), findsOneWidget);
    expect(find.text('Desactivados'), findsOneWidget);

    // En la sección de activos están los dos activos.
    expect(find.text('Producto activo'), findsOneWidget);
    expect(find.text('Otro activo'), findsOneWidget);
    expect(find.text('Producto desactivado'), findsNothing);
  });

  testWidgets('La sección de desactivados muestra el producto inactivo', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Desactivados'));
    await tester.pumpAndSettle();

    expect(find.text('Producto desactivado'), findsOneWidget);
    expect(find.text('Producto activo'), findsNothing);
    // La acción visible confirma que está desactivado.
    expect(find.text('Reactivar'), findsOneWidget);
    // Sus datos: categoría, precio y código.
    expect(find.textContaining('Bebidas'), findsWidgets);
    expect(find.textContaining('770003'), findsOneWidget);
  });

  testWidgets('La búsqueda funciona dentro de la sección seleccionada', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'otro');
    await tester.pumpAndSettle();

    expect(find.text('Otro activo'), findsOneWidget);
    expect(find.text('Producto activo'), findsNothing);
  });

  testWidgets('La pantalla de diagnóstico de cámara es independiente', (
    WidgetTester tester,
  ) async {
    // Debe existir y construirse sin el resto de la app (sin carrito ni GPS).
    await tester.pumpWidget(const MaterialApp(home: CameraDiagnosticScreen()));
    await tester.pump();

    expect(find.text('Diagnóstico cámara'), findsOneWidget);
    expect(find.text('Estado'), findsOneWidget);
  });
}
