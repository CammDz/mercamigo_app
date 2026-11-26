import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/local/key_value_store.dart';
import '../data/models/store_location.dart';

/// Configuración de la tienda.
///
/// La fuente de verdad es la tabla `public.tiendas` del proyecto Supabase
/// (la app puede leer las tiendas activas). Si el servidor todavía no tiene
/// una tienda activa se usa la configuración local guardada en el
/// dispositivo.
class SettingsRepository {
  SettingsRepository({required this.store, this.client});

  static const String _storeKey = 'mercamigo.settings.store';

  final KeyValueStore store;
  final SupabaseClient? client;

  /// Carga la tienda activa del servidor (o `null` si no hay ninguna).
  Future<StoreLocation?> loadActiveServerStore() async {
    final SupabaseClient? supabase = client;
    if (supabase == null) return null;
    try {
      final response = await supabase
          .from('tiendas')
          .select('id, nombre, direccion, latitud, longitud, activa')
          .eq('activa', true)
          .limit(1);
      final List<dynamic> rows = response as List<dynamic>;
      if (rows.isEmpty) return null;
      final Map<String, dynamic> row = rows.first as Map<String, dynamic>;
      return StoreLocation(
        id: row['id'] as String?,
        name: row['nombre'] as String?,
        address: row['direccion'] as String?,
        latitude: (row['latitud'] as num?)?.toDouble(),
        longitude: (row['longitud'] as num?)?.toDouble(),
        isActive: row['activa'] as bool? ?? true,
        isFromServer: true,
      );
    } catch (_) {
      // Sin servidor o sin respuesta: se usa la configuración local.
      return null;
    }
  }

  /// Configuración guardada en el dispositivo.
  Future<StoreLocation> loadLocalStoreLocation() async {
    final String? raw = await store.readString(_storeKey);
    if (raw == null || raw.isEmpty) return const StoreLocation();
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const StoreLocation();
      return StoreLocation.fromJson(decoded);
    } on FormatException {
      return const StoreLocation();
    }
  }

  /// Configuración efectiva: primero el servidor, luego lo local.
  Future<StoreLocation> loadStoreLocation() async {
    final StoreLocation? server = await loadActiveServerStore();
    if (server != null) return server;
    return loadLocalStoreLocation();
  }

  /// Guarda la configuración local de la tienda.
  Future<void> saveStoreLocation(StoreLocation location) =>
      store.writeString(_storeKey, jsonEncode(location.toJson()));
}
