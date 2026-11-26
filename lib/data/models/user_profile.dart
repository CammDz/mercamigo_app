import '../../core/utils/app_date_time.dart';

/// Perfil del usuario.
///
/// Refleja la tabla `public.perfiles`:
/// `id` (uuid, FK a `auth.users.id`), `nombre` y `creado_en`.
///
/// No contiene credenciales: Supabase Auth las gestiona.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String name;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'nombre': name,
        'creado_en': toServerDate(createdAt),
      };

  static UserProfile fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String? ?? '',
      name: json['nombre'] as String? ?? '',
      createdAt: parseServerDate(json['creado_en'] as String?) ??
          DateTime.now().toUtc(),
    );
  }
}
