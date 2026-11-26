import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/money.dart';
import '../../data/models/cart_item.dart';
import '../../data/models/product.dart';
import '../../data/models/product_category.dart';
import '../../data/models/purchase_origin.dart';
import '../../repositories/catalog_repository.dart';
import '../../state/cart_controller.dart';
import '../../state/origin_controller.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/primary_button.dart';
import '../widgets/product_image.dart';
import 'catalog_screen.dart';
import 'scanner_screen.dart';
import 'summary_screen.dart';

/// Carrito de compras.
///
/// Es el mismo carrito para el catálogo y el escáner. Todos los importes se
/// calculan a partir de los datos de los productos.
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  static const String routeName = '/cart';

  void _continueShopping(BuildContext context) {
    final PurchaseOrigin? origin = context.read<OriginController>().origin;
    final NavigatorState navigator = Navigator.of(context);
    final String target = origin == PurchaseOrigin.inStore
        ? ScannerScreen.routeName
        : CatalogScreen.routeName;
    navigator.popUntil(
      (Route<dynamic> route) =>
          route.settings.name == target || route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    final CartController cart = context.watch<CartController>();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppTopBar(
        title: 'Mi carrito',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double maxWidth = constraints.maxWidth >= 600 ? 620 : 460;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: cart.isEmpty
                      ? EmptyState(
                          icon: Icons.shopping_cart_outlined,
                          title: 'Tu carrito está vacío',
                          message:
                              'Agrega productos desde el catálogo o escaneando '
                              'productos en la tienda.',
                          actionLabel: 'Seguir comprando',
                          onAction: () => _continueShopping(context),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Text(
                              '${cart.totalUnits} producto(s) en el carrito',
                              style: AppText.body(
                                15,
                                weight: FontWeight.w600,
                                color: AppColors.muted,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...cart.items.map(
                              (CartItem item) => _CartRow(item: item),
                            ),
                            const SizedBox(height: 8),
                            _TotalsCard(cart: cart),
                            const SizedBox(height: 18),
                            PrimaryButton.outlined(
                              label: 'Seguir comprando',
                              icon: Icons.arrow_back,
                              onPressed: () => _continueShopping(context),
                            ),
                            const SizedBox(height: 12),
                            PrimaryButton(
                              label: 'Ver resumen de la orden',
                              icon: Icons.receipt_long_outlined,
                              onPressed: () => Navigator.of(context)
                                  .pushNamed(SummaryScreen.routeName),
                            ),
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Línea del carrito.
class _CartRow extends StatelessWidget {
  const _CartRow({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final CartController cart = context.read<CartController>();
    final Product product = _productFor(context, item);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ProductImage(product: product, size: 58, borderRadius: 8),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(15, color: AppColors.ink),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formatCopUnit(item.unitPrice)} c/u',
                      style: AppText.body(13, color: AppColors.ink),
                    ),
                    if (item.promotion != null)
                      Text(
                        'Promo ${item.promotion!.title}',
                        style: AppText.body(
                          12,
                          weight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => cart.remove(item.productId),
                icon: const Icon(Icons.delete_outline, color: AppColors.ink),
                tooltip: 'Eliminar',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              _MiniStepper(
                quantity: item.quantity,
                onDecrease: () => cart.decrease(item.productId),
                onIncrease: () => cart.increase(item.productId),
              ),
              const Spacer(),
              Text(
                formatCop(item.payableTotal),
                style: AppText.body(
                  17,
                  weight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          if (item.discount > 0) ...<Widget>[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Ahorro ${formatCop(item.discount)}',
                style: AppText.body(12, color: AppColors.ink),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Control de cantidad compacto para el carrito.
class _MiniStepper extends StatelessWidget {
  const _MiniStepper({
    required this.quantity,
    required this.onDecrease,
    required this.onIncrease,
  });

  final int quantity;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _MiniButton(icon: Icons.remove, onTap: onDecrease),
          Text(
            '$quantity',
            style: AppText.body(15, weight: FontWeight.w800),
          ),
          _MiniButton(icon: Icons.add, onTap: onIncrease),
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox(
        height: 36,
        width: 36,
        child: Icon(icon, size: 18, color: AppColors.ink),
      ),
    );
  }
}

/// Resumen de importes del carrito.
class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.cart});

  final CartController cart;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: <Widget>[
          _TotalRow(label: 'Subtotal', value: formatCop(cart.subtotal)),
          if (cart.discount > 0) ...<Widget>[
            const SizedBox(height: 8),
            _TotalRow(
              label: 'Descuentos',
              value: '-${formatCop(cart.discount)}',
              valueColor: AppColors.success,
            ),
          ],
          const Divider(height: 24),
          _TotalRow(
            label: 'Total a pagar en caja',
            value: formatCop(cart.total),
            valueColor: AppColors.primary,
            emphasize: true,
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.valueColor = AppColors.ink,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final Color valueColor;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: AppText.body(
              emphasize ? 17 : 15,
              weight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: AppText.body(
            emphasize ? 21 : 15,
            weight: FontWeight.w800,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

/// Recupera el producto (y su imagen) de una línea del carrito.
Product _productFor(BuildContext context, CartItem item) {
  final Product? product = context.read<CatalogRepository>().byId(item.productId);
  if (product != null) return product;
  return Product(
    id: item.productId,
    name: item.name,
    description: '',
    categoryId: item.categoryId,
    category: ProductCategory(
      id: item.categoryId,
      name: '',
      isActive: true,
    ),
    price: item.unitPrice,
    stock: 99,
    isActive: true,
    isDemo: true,
    codes: const <ProductCode>[],
  );
}
