import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/money.dart';
import '../../data/models/product.dart';
import 'product_image.dart';

/// Tarjeta de producto del listado (pantalla de categoría / búsqueda).
///
/// Reproduce el patrón del prototipo: tarjeta azul, imagen a la izquierda,
/// nombre y precio, y el botón circular "+" a la derecha.
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onAdd,
    this.onOpen,
    this.highlightPromotion = false,
  });

  final Product product;
  final VoidCallback onAdd;

  /// Abre el detalle del producto (para elegir cantidades).
  final VoidCallback? onOpen;

  /// Muestra la promoción como aviso de demostración.
  final bool highlightPromotion;

  @override
  Widget build(BuildContext context) {
    final PromotionBadge? badge = _promotionBadge;
    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                ProductImage(product: product, size: 65, borderRadius: 8),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(16, color: AppColors.ink),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Precio: ${formatCopUnit(product.price)}',
                        style: AppText.body(
                          19,
                          weight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      if (badge != null) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          badge.text,
                          style: AppText.body(
                            14,
                            weight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _AddCircleButton(onTap: onAdd),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PromotionBadge? get _promotionBadge {
    final promotion = product.promotion;
    if (promotion == null) return null;
    return PromotionBadge(
      text: 'Promoción ${promotion.title}',
      isDemo: !highlightPromotion,
    );
  }
}

/// Etiqueta de promoción con el título de la regla.
class PromotionBadge {
  const PromotionBadge({required this.text, required this.isDemo});

  final String text;

  /// `true` cuando la promoción se muestra como dato de demostración.
  final bool isDemo;
}

/// Botón circular "+" del listado.
class _AddCircleButton extends StatelessWidget {
  const _AddCircleButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(
        side: BorderSide(color: Colors.white, width: 2.2),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.add, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}
