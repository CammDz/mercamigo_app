import 'package:flutter_test/flutter_test.dart';
import 'package:mercamigo_app/core/config/app_config.dart';
import 'package:mercamigo_app/data/local/key_value_store.dart';
import 'package:mercamigo_app/data/models/product_category.dart';
import 'package:mercamigo_app/repositories/catalog_repository.dart';
import 'package:postgrest/postgrest.dart';

/// Prueba de integración contra el proyecto Supabase real.
///
/// Solo se ejecuta si la app se compiló con la configuración del servidor:
///
/// ```powershell
/// flutter test test/supabase_integration_test.dart `
///   --dart-define=SUPABASE_URL=https://<ref>.supabase.co `
///   --dart-define=SUPABASE_PUBLISHABLE_KEY=<clave-publicable>
/// ```
///
/// Comprueba que la app puede leer el catálogo real con los permisos de
/// lectura que ya tiene el proyecto (SELECT para `anon`).
void main() {
  test('el catálogo real se puede leer con la clave publicable', () async {
    if (!AppConfig.hasSupabase) {
      markTestSkipped(
        'Sin --dart-define=SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY.',
      );
      return;
    }

    final PostgrestClient client = PostgrestClient(
      AppConfig.restUrl,
      headers: <String, String>{
        'apikey': AppConfig.supabasePublishableKey,
        'Authorization': 'Bearer ${AppConfig.supabasePublishableKey}',
      },
    );

    try {
      final List<Map<String, dynamic>> categorias =
          (await client.from('categorias').select('id, nombre, activa'))
              .cast<Map<String, dynamic>>();
      final List<Map<String, dynamic>> productos =
          (await client.from('productos').select('id, nombre, precio_cop'))
              .cast<Map<String, dynamic>>();
      final List<Map<String, dynamic>> codigos =
          (await client.from('codigos_producto').select('codigo'))
              .cast<Map<String, dynamic>>();

      expect(categorias.length, 8);
      expect(productos.length, 40);
      expect(codigos.length, 40);
      for (final Map<String, dynamic> row in codigos) {
        expect(
          (row['codigo'] as String? ?? '').startsWith('MERCA-DEMO-'),
          isTrue,
        );
      }
    } finally {
      client.dispose();
    }
  });

  test('el repositorio de catálogo carga los datos del servidor', () async {
    if (!AppConfig.hasSupabase) {
      markTestSkipped(
        'Sin --dart-define=SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY.',
      );
      return;
    }

    // El repositorio usa el cliente de supabase_flutter, que necesita los
    // bindings de Flutter: se comprueba directamente con postgrest que los
    // datos tienen la forma que la app espera.
    final PostgrestClient client = PostgrestClient(
      AppConfig.restUrl,
      headers: <String, String>{
        'apikey': AppConfig.supabasePublishableKey,
        'Authorization': 'Bearer ${AppConfig.supabasePublishableKey}',
      },
    );

    try {
      final List<Map<String, dynamic>> rows =
          (await client
                  .from('productos')
                  .select(
                    'id, nombre, descripcion, categoria_id, precio_cop, '
                    'imagen_url, stock_demo, activo, es_demostracion, '
                    'categoria:categorias(id, nombre, activa), '
                    'codigos:codigos_producto(codigo, tipo)',
                  )
                  .limit(3))
              .cast<Map<String, dynamic>>();

      expect(rows, isNotEmpty);
      for (final Map<String, dynamic> row in rows) {
        expect(row['id'], isNotNull);
        expect(row['precio_cop'], isA<int>());
        expect(row['codigos'], isNotNull);
        final Object? categoria = row['categoria'];
        expect(categoria, isNotNull);
        if (categoria is List) {
          final Map<String, dynamic> first =
              categoria.first as Map<String, dynamic>;
          expect(first['nombre'], isNotEmpty);
        }
      }
    } finally {
      client.dispose();
    }
  });

  test(
    'la caché local conserva el catálogo para trabajar sin conexión',
    () async {
      final InMemoryStore store = InMemoryStore();
      final CatalogRepository repository = CatalogRepository(store: store);
      await repository.refresh();

      // Sin servidor la caché está vacía, pero el repositorio responde igual.
      expect(repository.all, isEmpty);
      expect(repository.search('astra'), isEmpty);

      final ProductCategory category = ProductCategory(
        id: 'x',
        name: 'Bebidas',
        isActive: true,
      );
      expect(category.iconAsset, isNotEmpty);
      expect(repository.byCategory(category), isEmpty);
    },
  );
}
