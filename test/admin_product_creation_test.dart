import 'package:flutter_test/flutter_test.dart';
import 'package:mercamigo_app/repositories/admin_catalog_repository.dart';

void main() {
  group('Alta de producto', () {
    test('no envía código: el servidor lo genera y lo devuelve', () async {
      String? calledName;
      Map<String, dynamic>? calledParams;

      final AdminCatalogRepository repository = AdminCatalogRepository(
        client: null,
        rpcOverride: (String name, Map<String, dynamic> params) async {
          calledName = name;
          calledParams = params;
          return <String, dynamic>{
            'producto_id': 'producto-uuid-1',
            'codigo': '78900000000001',
            'tipo': 'barras',
            'nombre': 'Arroz 500 g',
          };
        },
      );

      final CreatedProduct? created = await repository.createProduct(
        categoryId: 'categoria-uuid-1',
        name: 'Arroz 500 g',
        description: 'Grano largo',
        price: 3200,
      );

      expect(calledName, 'crear_producto');
      expect(calledParams, isNotNull);
      // La app nunca inventa ni envía el código principal.
      expect(calledParams!.containsKey('p_codigo'), isFalse);
      expect(calledParams!.containsKey('p_tipo_codigo'), isFalse);
      expect(calledParams!['p_categoria_id'], 'categoria-uuid-1');
      expect(calledParams!['p_precio_cop'], 3200);

      expect(created, isNotNull);
      expect(created!.id, 'producto-uuid-1');
      expect(created.code, '78900000000001');
      expect(created.type, 'barras');
      expect(created.name, 'Arroz 500 g');
    });

    test('falla si el servidor no devuelve el código generado', () async {
      final AdminCatalogRepository repository = AdminCatalogRepository(
        client: null,
        rpcOverride: (String name, Map<String, dynamic> params) async {
          return <String, dynamic>{'producto_id': 'producto-uuid-1'};
        },
      );

      await expectLater(
        repository.createProduct(
          categoryId: 'categoria-uuid-1',
          name: 'Producto',
          description: '',
          price: 1000,
        ),
        throwsA(isA<AdminCatalogException>()),
      );
    });

    test('los códigos adicionales se registran como barras', () async {
      Map<String, dynamic>? calledParams;
      final AdminCatalogRepository repository = AdminCatalogRepository(
        client: null,
        rpcOverride: (String name, Map<String, dynamic> params) async {
          calledParams = params;
          return const <String, dynamic>{};
        },
      );

      await repository.registerCode(
        productId: 'producto-uuid-1',
        code: '0123456789012',
      );

      expect(calledParams!['p_producto_id'], 'producto-uuid-1');
      expect(calledParams!['p_codigo'], '0123456789012');
      expect(calledParams!['p_tipo'], 'barras');
    });
  });
}
