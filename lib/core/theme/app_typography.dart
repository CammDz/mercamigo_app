
import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Familias tipográficas usadas en el prototipo de Figma.
/// Se empaquetan localmente (assets/fonts) para no depender de la red.
abstract final class AppFonts {
  /// Titulares: "MERCAMIGO", "Escaner", "Producto encontrado".
  static const String display = 'Jaro';

  /// Textos de interfaz y contenido: League Spartan.
  static const String body = 'LeagueSpartan';
}

/// Estilos tipográficos de la app.
///
/// Las dos familias son fuentes variables, por eso el eje `wght` se fija de
/// forma explícita con [FontVariation] (además de [FontWeight]) para que el
/// peso se vea igual en todos los dispositivos.
abstract final class AppText {
  static List<FontVariation> _wght(FontWeight weight) =>
      <FontVariation>[FontVariation('wght', weight.value.toDouble())];

  /// Título principal (display).
  static TextStyle display(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.ink,
    double? height,
  }) =>
      TextStyle(
        fontFamily: AppFonts.display,
        fontSize: size,
        height: height,
        color: color,
        fontWeight: weight,
        fontVariations: _wght(weight),
      );

  /// Texto de interfaz (body).
  static TextStyle body(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.ink,
    double? height,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: AppFonts.body,
        fontSize: size,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
        fontWeight: weight,
        fontVariations: _wght(weight),
      );
}
