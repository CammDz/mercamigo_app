import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/money.dart';
import '../../data/models/product.dart';
import '../../state/cart_controller.dart';
import '../widgets/product_image.dart';
import '../widgets/quantity_stepper.dart';
import 'cart_screen.dart';

/// Detalle del producto.
///
/// Se usa tanto para el resultado del escáner ("Producto encontrado") como
/// al abrir un producto desde el catálogo o la búsqueda.
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.product,
    this.origin = 'Catálogo',
  });

  static const String routeName = '/product-detail';

  final Product product;

  /// Texto que indica de dónde viene el producto.
  final String origin;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  int _quantity = 1;
  bool _added = false;

  Product get _product => widget.product;

  Future<void> _addToCart() async {
    final CartController cart = context.read<CartController>();
    await cart.add(_product, quantity: _quantity);
    if (!mounted) return;
    setState(() => _added = true);
    await Navigator.of(context).pushNamed(CartScreen.routeName);
  }

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final bool wide = width >= 600;
    final double maxWidth = wide ? 520 : 400;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 29, 16, 12),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    widget.origin == 'Catálogo'
                        ? 'Detalle del producto'
                        : 'Producto encontrado',
                    textAlign: TextAlign.center,
                    style: AppText.display(25, color: Colors.white),
                  ),
                  const SizedBox(height: 50),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(37),
                    ),
                    child: Stack(
                      children: <Widget>[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            const SizedBox(height: 38),
                            Center(
                              child: ProductImage(
                                product: _product,
                                size: 192,
                                fallbackSize: 192,
                                borderRadius: 12,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _product.name,
                              textAlign: TextAlign.center,
                              style: AppText.body(19, weight: FontWeight.w400),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _sizeLabel(_product.name),
                              textAlign: TextAlign.center,
                              style: AppText.body(
                                16,
                                color: AppColors.mutedWarm,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formatCopUnit(_product.price),
                              textAlign: TextAlign.center,
                              style: AppText.body(24, weight: FontWeight.w800),
                            ),
                            const SizedBox(height: 14),
                            QuantityStepper(
                              quantity: _quantity,
                              canDecrease: _quantity > 1,
                              canIncrease: _quantity < _product.stock,
                              onDecrease: () => setState(
                                () => _quantity = (_quantity - 1).clamp(1, 999),
                              ),
                              onIncrease: () => setState(() {
                                _quantity = (_quantity + 1).clamp(
                                  1,
                                  _product.stock,
                                );
                              }),
                            ),
                            const SizedBox(height: 14),
                            _AddToOrderButton(onPressed: _addToCart),
                          ],
                        ),
                        Positioned(
                          top: 3,
                          right: 4,
                          child: _SuccessCheck(visible: _added),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 63),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 22,
                    ),
                    label: Text(
                      'Cerrar',
                      style: AppText.body(16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _sizeLabel(String name) {
    final RegExpMatch? match = RegExp(
      r'\b\d+(?:[.,]\d+)?\s?(?:ml|l|g|kg)\b',
      caseSensitive: false,
    ).firstMatch(name);
    return match?.group(0) ?? widget.product.category.name;
  }
}

class _AddToOrderButton extends StatelessWidget {
  const _AddToOrderButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 47.5,
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Center(
            child: Text(
              'Agregar a mi orden',
              style: AppText.body(
                20,
                weight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Check verde de confirmación (elemento del prototipo).
class _SuccessCheck extends StatelessWidget {
  const _SuccessCheck({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 220),
      child: Container(
        height: 37,
        width: 37,
        decoration: const BoxDecoration(
          color: AppColors.success,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, color: Colors.white, size: 22),
      ),
    );
  }
}
