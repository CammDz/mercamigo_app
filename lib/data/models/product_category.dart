import 'package:flutter/material.dart';

import '../catalog/local_assets.dart';

/// Categoría del catálogo.
///
/// Refleja la tabla `public.categorias` del proyecto Supabase:
/// `id` (uuid), `nombre` y `activa`.
///
/// El ícono y el color son recursos **locales** de la app: la base de datos
/// no tiene imágenes de categoría.
class ProductCategory {
  const ProductCategory({
    required this.id,
    required this.name,
    required this.isActive,
  });

  /// `categorias.id` (uuid).
  final String id;

  /// `categorias.nombre`.
  final String name;

  /// `categorias.activa`.
  final bool isActive;

  /// Recurso local con el ícono de la categoría (o cadena vacía si no hay).
  String get iconAsset => LocalAssets.categoryIcon(name) ?? '';

  /// `true` cuando hay un ícono local para la categoría.
  bool get hasIcon => LocalAssets.categoryIcon(name) != null;

  /// Color de respaldo de la categoría.
  Color get color => LocalAssets.categoryColor(name);

  ProductCategory copyWith({String? name, bool? isActive}) {
    return ProductCategory(
      id: id,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'isActive': isActive,
  };

  static ProductCategory fromJson(Map<String, dynamic> json) {
    return ProductCategory(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      isActive: json['isActive'] as bool? ?? true,
    );
  }
}
