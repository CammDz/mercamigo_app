import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/user_profile.dart';

/// Acceso al perfil del usuario (`public.perfiles`).
///
/// El perfil solo guarda el nombre y las fechas. Los permisos NO se derivan
/// de aquí: el rol vive en `roles_usuario`, que solo escribe el servidor.
class ProfileRepository {
  const ProfileRepository({this.client});

  final SupabaseClient? client;

  /// `true` cuando hay servidor.
  bool get isAvailable => client != null;

  /// Carga el perfil del usuario autenticado.
  Future<UserProfile?> loadProfile(String userId) async {
    final SupabaseClient? supabase = client;
    if (supabase == null) return null;
    try {
      final List<Map<String, dynamic>> rows =
          (await supabase
                  .from('perfiles')
                  .select('id, nombre, creado_en')
                  .eq('id', userId)
                  .limit(1))
              .cast<Map<String, dynamic>>();
      if (rows.isEmpty) return null;
      return UserProfile.fromJson(rows.first);
    } catch (_) {
      return null;
    }
  }

  /// Actualiza el nombre del usuario autenticado.
  Future<bool> updateName(String userId, String name) async {
    final SupabaseClient? supabase = client;
    if (supabase == null) return false;
    try {
      await supabase
          .from('perfiles')
          .update(<String, dynamic>{'nombre': name.trim()})
          .eq('id', userId);
      return true;
    } catch (_) {
      return false;
    }
  }
}
