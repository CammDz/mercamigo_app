import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/admin_product.dart';

/// Resultado de cargar el catálogo en modo administrador.
class AdminCatalogSnapshot {
  const AdminCatalogSnapshot({
    this.categories = const <AdminCategory>[],
    this.products = const <AdminProduct>[],
  });

  final List<AdminCategory> categories;
  final List<AdminProduct> products;

  bool get isEmpty => products.isEmpty && categories.isEmpty;
}

/// Producto recién creado, con el código que generó el servidor.
///
/// El código **no** lo escribe la app: `public.crear_producto` lo genera
/// (numérico, único, de 14 dígitos) y lo devuelve para mostrarlo.
class CreatedProduct {
  const CreatedProduct({
    required this.id,
    required this.code,
    required this.type,
    required this.name,
  });

  final String id;
  final String code;
  final String type;
  final String name;
}

/// Categoría del catálogo (solo se lee: en esta etapa no se administran).
class AdminCategory {
  const AdminCategory({
    required this.id,
    required this.name,
    required this.isActive,
  });

  final String id;
  final String name;
  final bool isActive;
}

/// Ejecuta una RPC del servidor. Se puede sustituir en las pruebas.
typedef AdminRpcInvoker = Future<Object?> Function(
  String name,
  Map<String, dynamic> params,
);

/// Acceso al catálogo en modo **administrador**.
///
/// No usa la caché local del comprador: el comprador nunca debe ver
/// productos inactivos, y su caché se conserva limpia aunque el
/// administrador entre y salga.
///
/// Todas las escrituras pasan por las funciones del servidor, que vuelven a
/// comprobar el rol: ocultar botones NO es la medida de autorización.
class AdminCatalogRepository {
  AdminCatalogRepository({required this.client, this.rpcOverride});

  final SupabaseClient? client;

  /// Sustituto de `client.rpc` (solo para pruebas).
  final AdminRpcInvoker? rpcOverride;

  /// `true` cuando hay servidor configurado.
  bool get isConfigured => client != null;

  Future<List<Map<String, dynamic>>> loadPromotions() async {
    final SupabaseClient? db = client;
    if (db == null) return const <Map<String, dynamic>>[];
    final rows = await db
        .from('promociones')
        .select(
          'id, nombre, tipo, cantidad_compra, cantidad_gratis, cantidad_paquete, '
          'precio_paquete_cop, banner_url, activa, '
          'productos:promocion_productos(producto:productos(id, nombre))',
        )
        .order('creado_en', ascending: false);
    return (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList();
  }

  Future<void> savePromotion({
    required String name,
    required String type,
    required int buyQuantity,
    required int freeQuantity,
    required int packageQuantity,
    required int packagePrice,
    required String? bannerUrl,
    required List<String> productIds,
  }) async {
    final SupabaseClient? db = client;
    if (db == null) {
      throw const AdminCatalogException('Supabase no está configurado.');
    }
    if (productIds.isEmpty) {
      throw const AdminCatalogException('Selecciona al menos un producto.');
    }
    final Object? result = await db.rpc(
      'guardar_promocion',
      params: <String, dynamic>{
        'p_nombre': name,
        'p_tipo': type,
        'p_cantidad_compra': buyQuantity,
        'p_cantidad_gratis': freeQuantity,
        'p_cantidad_paquete': packageQuantity,
        'p_precio_paquete_cop': type == 'precio_paquete' ? packagePrice : null,
        'p_banner_url': bannerUrl,
        'p_productos': productIds,
      },
    );
    if (result == null) {
      throw const AdminCatalogException('Supabase no confirmó la promoción.');
    }
  }

  Future<void> setPromotionActive(String id, bool active) async {
    final SupabaseClient? db = client;
    if (db == null) {
      throw const AdminCatalogException('Supabase no está configurado.');
    }
    await db
        .from('promociones')
        .update(<String, dynamic>{'activa': active})
        .eq('id', id);
  }

  /// Carga productos (activos e inactivos) y categorías.
  Future<AdminCatalogSnapshot> load() async {
    final SupabaseClient? client = this.client;
    if (client == null) return const AdminCatalogSnapshot();

    final Object categoriesResponse = await client
        .from('categorias')
        .select('id, nombre, activa');
    final List<AdminCategory> categories = <AdminCategory>[];
    for (final Map<String, dynamic> row
        in (categoriesResponse as List<dynamic>)
            .whereType<Map<String, dynamic>>()) {
      categories.add(
        AdminCategory(
          id: row['id'] as String? ?? '',
          name: row['nombre'] as String? ?? '',
          isActive: row['activa'] as bool? ?? true,
        ),
      );
    }

    final Object productsResponse = await client
        .from('productos')
        .select(
          'id, nombre, descripcion, precio_cop, imagen_url, activo, categoria_id, '
          'categoria:categorias(id, nombre), '
          'codigos:codigos_producto(id, codigo, tipo)',
        );

    final List<AdminProduct> products = <AdminProduct>[];
    for (final Map<String, dynamic> row
        in (productsResponse as List<dynamic>)
            .whereType<Map<String, dynamic>>()) {
      products.add(
        AdminProduct(
          id: row['id'] as String? ?? '',
          name: row['nombre'] as String? ?? '',
          description: row['descripcion'] as String? ?? '',
          categoryId: row['categoria_id'] as String? ?? '',
          categoryName: _categoryName(row['categoria']),
          price: (row['precio_cop'] as num?)?.toInt() ?? 0,
          isActive: row['activo'] as bool? ?? true,
          imageUrl: row['imagen_url'] as String?,
          codes: _codesFromEmbed(row['codigos']),
        ),
      );
    }

    return AdminCatalogSnapshot(categories: categories, products: products);
  }

  /// Crea un producto. El servidor genera y devuelve su código principal.
  ///
  /// No se envía `p_codigo` ni `p_tipo_codigo`: la función remota los ignora y
  /// genera un código numérico único de 14 dígitos de tipo `barras`.
  Future<CreatedProduct?> createProduct({
    required String categoryId,
    required String name,
    required String description,
    required int price,
    String? imageUrl,
  }) async {
    final Map<String, dynamic> result = await _rpcJson(
      'crear_producto',
      <String, dynamic>{
        'p_categoria_id': categoryId,
        'p_nombre': name,
        'p_descripcion': description,
        'p_precio_cop': price,
        'p_imagen_url': imageUrl,
      },
    );
    final String id = (result['producto_id'] ?? result['id']) as String? ?? '';
    final String code = result['codigo'] as String? ?? '';
    if (id.isEmpty || code.isEmpty) {
      throw const AdminCatalogException(
        'El servidor no devolvió el código del producto. '
        'Recarga la lista antes de volver a intentarlo.',
      );
    }
    return CreatedProduct(
      id: id,
      code: code,
      type: result['tipo'] as String? ?? 'barras',
      name: result['nombre'] as String? ?? name,
    );
  }

  /// Edita un producto existente.
  Future<void> editProduct({
    required String id,
    required String name,
    required String description,
    required String categoryId,
    required int price,
    String? imageUrl,
  }) async {
    await _rpc('editar_producto', <String, dynamic>{
      'p_producto_id': id,
      'p_nombre': name,
      'p_descripcion': description,
      'p_categoria_id': categoryId,
      'p_precio_cop': price,
      'p_imagen_url': imageUrl,
    });
  }

  /// Desactiva (borrado lógico) o reactiva un producto.
  Future<void> setProductActive({
    required String id,
    required bool active,
  }) async {
    await _rpc('establecer_estado_producto', <String, dynamic>{
      'p_producto_id': id,
      'p_activo': active,
    });
  }

  /// Registra un **código adicional** (de barras) para un producto.
  ///
  /// El código principal se generó al crear el producto y no se modifica. El
  /// servidor rechaza duplicados y este código se conserva como adicional.
  Future<void> registerCode({
    required String productId,
    required String code,
  }) async {
    await _rpc('registrar_codigo_producto', <String, dynamic>{
      'p_producto_id': productId,
      'p_codigo': code,
      'p_tipo': 'barras',
    });
  }

  /// Carga la tienda configurada (la primera, activa o no).
  ///
  /// Un administrador puede ver también las tiendas inactivas, así que no
  /// se filtra por `activa` como hace la vista del comprador.
  Future<AdminStore?> loadStore() async {
    final SupabaseClient? client = this.client;
    if (client == null) return null;
    final Object response = await client
        .from('tiendas')
        .select('id, nombre, direccion, latitud, longitud, activa')
        .limit(1);
    final List<dynamic> rows = response as List<dynamic>;
    if (rows.isEmpty) return null;
    final Map<String, dynamic> row = rows.first as Map<String, dynamic>;
    return AdminStore(
      id: row['id'] as String?,
      name: row['nombre'] as String? ?? '',
      address: row['direccion'] as String? ?? '',
      latitude: (row['latitud'] as num?)?.toDouble(),
      longitude: (row['longitud'] as num?)?.toDouble(),
      isActive: row['activa'] as bool? ?? true,
    );
  }

  /// Guarda la tienda.
  ///
  /// Si la tienda ya existe se edita **esa misma** (por su id): nunca se crea
  /// una duplicada. Solo se escribe al pulsar "Guardar cambios".
  Future<void> saveStore({
    required String? id,
    required String name,
    required String address,
    required double? latitude,
    required double? longitude,
  }) async {
    await _rpc('configurar_tienda', <String, dynamic>{
      'p_tienda_id': id,
      'p_nombre': name,
      'p_direccion': address,
      'p_latitud': latitude,
      'p_longitud': longitude,
      'p_activar': true,
    });
  }

  /// Llama a una RPC de administracion sin usar el resultado.
  Future<void> _rpc(String name, Map<String, dynamic> params) async {
    await _rpcJson(name, params);
  }

  /// Llama a una RPC de administracion y devuelve su resultado en JSON.
  Future<Map<String, dynamic>> _rpcJson(
    String name,
    Map<String, dynamic> params,
  ) async {
    final AdminRpcInvoker? override = rpcOverride;
    if (override != null) {
      try {
        final Object? result = await override(name, params);
        if (result is Map<String, dynamic>) return result;
        if (result is Map) return Map<String, dynamic>.from(result);
        return const <String, dynamic>{};
      } catch (error) {
        throw AdminCatalogException(
          'No se pudo completar la operación: $error',
        );
      }
    }

    final SupabaseClient? client = this.client;
    if (client == null) {
      throw const AdminCatalogException(
        'El servidor no está configurado en esta compilación.',
      );
    }
    try {
      final Object? result = await client.rpc(name, params: params);
      if (result is Map<String, dynamic>) return result;
      if (result is Map) return Map<String, dynamic>.from(result);
      return const <String, dynamic>{};
    } on PostgrestException catch (error) {
      throw AdminCatalogException(_friendlyMessage(error));
    } catch (error) {
      throw AdminCatalogException('No se pudo completar la operación: $error');
    }
  }

  /// Traduce el error del servidor a un mensaje entendible.
  String _friendlyMessage(PostgrestException error) {
    final String message = error.message.trim();
    if (message.isEmpty) return 'El servidor rechazó la operación.';
    if (message.contains('Ese codigo ya pertenece')) {
      return 'Ese código ya pertenece a otro producto. '
          'Corrige el producto o usa otro código.';
    }
    if (message.contains('ya esta registrado en este producto')) {
      return 'Ese código ya está registrado en este producto.';
    }
    if (message.contains('Solo un administrador')) {
      return 'Tu sesión no tiene permisos de administrador. '
          'Vuelve a iniciar sesión.';
    }
    if (message.contains('La categoria no existe')) {
      return 'La categoría no existe o no está activa.';
    }
    return message;
  }

  String _categoryName(Object? embed) {
    final Map<String, dynamic>? row = embed is List
        ? (embed.isEmpty ? null : embed.first as Map<String, dynamic>)
        : (embed as Map<String, dynamic>?);
    return row?['nombre'] as String? ?? '';
  }

  List<ProductCode> _codesFromEmbed(Object? embed) {
    final List<Map<String, dynamic>> rows = embed is List
        ? embed.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[if (embed is Map<String, dynamic>) embed];
    return rows
        .map(
          (Map<String, dynamic> row) => ProductCode(
            id: row['id'] as String? ?? '',
            code: row['codigo'] as String? ?? '',
            type: row['tipo'] as String? ?? 'barras',
          ),
        )
        .where((ProductCode code) => code.code.isNotEmpty)
        .toList(growable: false);
  }
}

/// Error de una operación administrativa, con un mensaje ya traducido.
class AdminCatalogException implements Exception {
  const AdminCatalogException(this.message);

  final String message;

  @override
  String toString() => message;
}
