import 'package:flutter/material.dart';

/// Paleta de colores extraída del prototipo de Figma (archivo "App").
/// Los valores coinciden literalmente con los nodos del diseño.
abstract final class AppColors {
  /// Azul principal de marca (#5D9EF3): tarjetas de producto, botones, acentos.
  static const Color primary = Color(0xFF5D9EF3);

  /// Azul brillante del degradado superior de la pantalla de bienvenida.
  static const Color primaryBright = Color(0xFF4797FF);

  /// Tono inferior del degradado de bienvenida (rgb(84,136,203) al 87%).
  static const Color primaryDeep = Color(0xFF5488CB);

  /// Negro puro de titulares y textos de la marca.
  static const Color ink = Color(0xFF000000);

  /// Negro suave usado en el número de orden.
  static const Color inkSoft = Color(0xFF010101);

  /// Gris azulado de textos secundarios (#5C6170).
  static const Color muted = Color(0xFF5C6170);

  /// Gris cálido del texto de presentación del producto (#625A5A).
  static const Color mutedWarm = Color(0xFF625A5A);

  /// Blanco de tarjetas y superficies.
  static const Color surface = Color(0xFFFFFFFF);

  /// Gris muy claro para fondos de campos y separadores.
  static const Color surfaceSoft = Color(0xFFF2F3F5);

  /// Línea divisoria de la pantalla de resumen.
  static const Color line = Color(0xFFDDDDDD);

  /// Relleno de los círculos grises (controles de cantidad y categorías).
  static const Color grayFill = Color(0xFFD7D7D7);

  /// Contorno de esos círculos (#606060).
  static const Color grayStroke = Color(0xFF606060);

  /// Borde del contenedor de la orden generada (#999999).
  static const Color grayBorder = Color(0xFF999999);

  /// Borde del botón "Compartir Orden" (#595959).
  static const Color grayBorderDark = Color(0xFF595959);

  /// Verde del check de "Producto encontrado".
  static const Color success = Color(0xFF34A853);

  /// Rojo de acciones destructivas.
  static const Color danger = Color(0xFFC62828);

  /// Ámbar de avisos informativos (datos de demostración).
  static const Color warning = Color(0xFFB26A00);

  // ---------------------------------------------------------------------
  // Paleta del rediseño (marcos más recientes de Figma).
  // ---------------------------------------------------------------------

  /// Fondo general gris muy claro de las pantallas interiores (#F4F5F7).
  static const Color background = Color(0xFFF4F5F7);

  /// Inicio del degradado azul de las cabeceras (#5D9EF3).
  static const Color headerStart = Color(0xFF5B9BF0);

  /// Fin del degradado azul de las cabeceras (#76AEF8).
  static const Color headerEnd = Color(0xFF76AEF8);

  /// Contenedor lila de chips, avisos y botones secundarios (#EADDff).
  static const Color lilac = Color(0xFFEADDff);

  /// Lila muy suave para fondos de bloques informativos.
  static const Color lilacSoft = Color(0xFFF3ECFF);

  /// Texto oscuro del rediseño (casi negro azulado).
  static const Color textDark = Color(0xFF1C1B1F);

  /// Texto secundario del rediseño.
  static const Color textMuted = Color(0xFF6B6B72);

  /// Verde claro de la píldora "Entregado".
  static const Color successSoft = Color(0xFF9BE8A4);

  /// Rojo claro de la píldora "Cancelada".
  static const Color dangerSoft = Color(0xFFF58E8E);

  /// Relleno de los marcadores de mapa del prototipo.
  static const Color mapFill = Color(0xFFE8F0E4);

  /// Borde suave de tarjetas y campos (#E3E3E8).
  static const Color cardBorder = Color(0xFFE3E3E8);
}
