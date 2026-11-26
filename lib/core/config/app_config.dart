/// Configuración de la aplicación.
///
/// Los datos de Supabase se inyectan **en tiempo de compilación** con
/// `--dart-define`, de forma que no hay ninguna credencial escrita en el
/// código fuente ni en el repositorio.
///
/// ```powershell
/// flutter build apk --release `
///   --dart-define=SUPABASE_URL=https://<ref>.supabase.co `
///   --dart-define=SUPABASE_PUBLISHABLE_KEY=<clave-publicable>
/// ```
///
/// La clave que se usa es la **publicable** (`sb_publishable_...`), pensada
/// para ir dentro de la app. Nunca la clave `service_role` ni la contraseña
/// de PostgreSQL.
abstract final class AppConfig {
  const AppConfig._();

  /// URL del proyecto Supabase.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Clave publicable del proyecto Supabase.
  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  /// `true` cuando la app se compiló con la configuración de Supabase.
  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  /// URL base de la API REST de PostgREST.
  ///
  /// Es la URL del proyecto con el sufijo `/rest/v1`.
  static String get restUrl =>
      supabaseUrl.endsWith('/rest/v1') ? supabaseUrl : '$supabaseUrl/rest/v1';

  /// Nombre visible de la app.
  static const String appName = 'Mercamigo';

  /// Longitud del código de recuperación de contraseña (OTP por correo).
  ///
  /// Es la longitud que tiene realmente configurada el proyecto de Supabase
  /// (Authentication → Email → **Email OTP Length**). La app no la inventa:
  /// se usa en el campo de entrada, en los límites, en la validación, en el
  /// botón de verificar y en los mensajes.
  static const int recoveryOtpLength = 8;
}
