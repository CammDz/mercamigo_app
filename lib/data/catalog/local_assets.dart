import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/text_normalizer.dart';

/// Recursos **locales** de la app: íconos de categoría e imágenes de
/// producto.
///
/// La base de datos guarda `imagen_url` pero está vacía, así que la app usa
/// estos recursos empaquetados. Nunca se descarga una imagen remota: la app
/// sigue siendo utilizable sin conexión.
abstract final class LocalAssets {
  const LocalAssets._();

  /// Ícono (PNG del prototipo) por clave de categoría.
  static const Map<String, String> _categoryIcons = <String, String>{
    'bebidas': 'assets/figma/cat_bebidas.png',
    'snacks': 'assets/figma/cat_snacks.png',
    'postres': 'assets/figma/cat_postres.png',
    'lacteos': 'assets/figma/cat_lacteos.png',
    'cuidado personal': 'assets/figma/cat_cuidado.png',
    'hogar': 'assets/figma/cat_hogar.png',
    'mascotas': 'assets/figma/cat_mascotas.png',
    'despensa': 'assets/figma/cat_despensa.png',
  };

  /// Color de respaldo por clave de categoría.
  static const Map<String, int> _categoryColors = <String, int>{
    'bebidas': 0xFF5D9EF3,
    'snacks': 0xFFF2A93B,
    'postres': 0xFFE46C8A,
    'lacteos': 0xFF49A0C7,
    'cuidado personal': 0xFF7C6BD6,
    'hogar': 0xFF3FA97A,
    'mascotas': 0xFFC98A3B,
    'despensa': 0xFF6B8E23,
  };

  /// Imágenes del prototipo reutilizadas para productos del catálogo.
  static const Map<String, String> _productImages = <String, String>{
    'astra cola original 500 ml': 'assets/figma/product_astra.png',
    'agua original 600 ml': 'assets/figma/product_agua.png',
    'jugo de naranja 500 ml': 'assets/figma/product_jugo.png',
  };

  /// Clave normalizada de una categoría (sin mayúsculas ni tildes).
  static String categoryKey(String name) => normalizeText(name);

  /// Ícono local de la categoría, o `null` si no hay uno específico.
  static String? categoryIcon(String name) => _categoryIcons[categoryKey(name)];

  /// Color de respaldo de la categoría.
  static Color categoryColor(String name) =>
      Color(_categoryColors[categoryKey(name)] ?? AppColors.primary.toARGB32());

  /// Imagen local de un producto por su nombre, o `null`.
  static String? productImage(String productName) =>
      _productImages[normalizeText(productName)];

  /// Imágenes que el administrador puede elegir para un producto.
  ///
  /// Se guardan en `productos.imagen_url` como ruta del recurso
  /// (`assets/...`), no como URL: la app sigue sin depender de la red.
  static const List<({String label, String asset})> selectableImages =
      <({String label, String asset})>[
        (label: 'Astra Cola', asset: 'assets/figma/product_astra.png'),
        (label: 'Agua', asset: 'assets/figma/product_agua.png'),
        (label: 'Jugo de naranja', asset: 'assets/figma/product_jugo.png'),
        (label: 'Bebidas', asset: 'assets/figma/cat_bebidas.png'),
        (label: 'Snacks', asset: 'assets/figma/cat_snacks.png'),
        (label: 'Postres', asset: 'assets/figma/cat_postres.png'),
        (label: 'Lácteos', asset: 'assets/figma/cat_lacteos.png'),
        (label: 'Cuidado personal', asset: 'assets/figma/cat_cuidado.png'),
        (label: 'Hogar', asset: 'assets/figma/cat_hogar.png'),
        (label: 'Mascotas', asset: 'assets/figma/cat_mascotas.png'),
        (label: 'Despensa', asset: 'assets/figma/cat_despensa.png'),
        (label: 'Tienda', asset: 'assets/figma/icon_shop.png'),
      ];
}
