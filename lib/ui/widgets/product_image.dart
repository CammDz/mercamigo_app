import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/product.dart';

/// Imagen de un producto.
///
/// Prioriza la foto real del producto:
///
/// * Si el administrador subió una foto desde el celular, `imagen_url` es una
///   dirección de Supabase Storage y se muestra con `Image.network`.
/// * Si la foto es un recurso empaquetado, se muestra con `Image.asset`.
/// * Si el producto no tiene foto propia, se muestra un **placeholder
///   neutro** (no las imágenes genéricas de demostración).
class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    required this.product,
    this.size = 56,
    this.borderRadius = 10,
    this.fallbackSize,
  });

  final Product product;
  final double size;
  final double borderRadius;
  final double? fallbackSize;

  @override
  Widget build(BuildContext context) {
    final String? asset = product.localImageAsset;
    if (asset != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (
            BuildContext context,
            Object error,
            StackTrace? stack,
          ) => _fallback(),
        ),
      );
    }

    final String? remote = product.hasRemoteImage ? product.imageUrl : null;
    if (remote != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.network(
          remote,
          width: size,
          height: size,
          fit: BoxFit.contain,
          loadingBuilder:
              (BuildContext context, Widget child, ImageChunkEvent? progress) {
                if (progress == null) return child;
                return _fallback();
              },
          errorBuilder: (
            BuildContext context,
            Object error,
            StackTrace? stack,
          ) => _fallback(),
        ),
      );
    }

    return _fallback();
  }

  /// Placeholder neutro: un recuadro gris con el ícono del carrito.
  ///
  /// Es neutro a proposito (gris): con el color de la categoria el icono
  /// desaparecia sobre las tarjetas de producto, que usan ese mismo color.
  Widget _fallback() {
    final double dimension = fallbackSize ?? size;
    return Container(
      width: dimension,
      height: dimension,
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.shopping_basket_outlined,
        size: dimension * 0.5,
        color: AppColors.muted,
      ),
    );
  }
}
