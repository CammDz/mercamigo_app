/// Validaciones de entrada compartidas por las pantallas de autenticación.
abstract final class Validators {
  /// Expresión regular de un correo con formato válido.
  static final RegExp emailPattern =
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Longitud mínima de contraseña (la de Supabase Auth por defecto).
  static const int minPasswordLength = 6;

  /// `true` si el correo tiene un formato válido.
  static bool isEmail(String value) =>
      emailPattern.hasMatch(value.trim());

  /// `true` si la contraseña cumple la longitud mínima.
  static bool isPasswordValid(String value) =>
      value.length >= minPasswordLength;

  /// `true` si la contraseña y su confirmación coinciden.
  static bool passwordsMatch(String password, String confirmation) =>
      password == confirmation;

  /// Mensaje de error de un correo inválido (o `null` si es válido).
  static String? emailError(String value) {
    if (value.trim().isEmpty) return 'Escribe tu correo.';
    if (!isEmail(value)) return 'El correo no tiene un formato válido.';
    return null;
  }

  /// Mensaje de error de una contraseña inválida (o `null` si es válida).
  static String? passwordError(String value) {
    if (value.isEmpty) return 'Escribe tu contraseña.';
    if (!isPasswordValid(value)) {
      return 'La contraseña debe tener al menos $minPasswordLength caracteres.';
    }
    return null;
  }

  /// Mensaje de error de la confirmación (o `null` si coincide).
  static String? confirmationError(String password, String confirmation) {
    if (confirmation.isEmpty) return 'Repite la contraseña.';
    if (!passwordsMatch(password, confirmation)) {
      return 'Las contraseñas no coinciden.';
    }
    return null;
  }

  /// Mensaje de error del nombre (o `null` si es válido).
  static String? nameError(String value) {
    if (value.trim().isEmpty) return 'Escribe tu nombre.';
    return null;
  }
}
