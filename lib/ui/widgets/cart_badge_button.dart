import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../state/cart_controller.dart';
import '../screens/cart_screen.dart';

/// Botón del carrito con contador de unidades.
///
/// Aparece en la cabecera de las pantallas de catálogo, productos, resumen y
/// escáner.
class CartBadgeButton extends StatelessWidget {
  const CartBadgeButton({
    super.key,
    this.color = AppColors.ink,
    this.size = 40,
    this.tint,
  });

  final Color color;
  final double size;

  /// Tinte opcional del icono.
  ///
  /// El recurso original es un icono negro: en las pantallas de fondo oscuro
  /// (el escáner) se tiñe de blanco para que se vea. Sin este parámetro el
  /// icono se muestra tal cual, como en el resto de pantallas.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final int count = context.select<CartController, int>(
      (CartController controller) => controller.totalUnits,
    );

    return InkWell(
      onTap: () => Navigator.of(context).pushNamed(CartScreen.routeName),
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: size,
        width: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Padding(
              // Margen corto: el icono del carrito se ve mas grande sin
              // que el contador lo tape.
              padding: const EdgeInsets.all(4),
              child: Icon(
                // Se usa el icono de Material y no `assets/figma/icon_cart.png`
                // porque ese recurso trae el globo con el "1" dibujado.
                Icons.shopping_cart_outlined,
                size: size - 8,
                color: tint ?? color,
              ),
            ),
            if (count > 0)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.danger,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
