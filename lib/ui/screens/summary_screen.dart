import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/money.dart';
import '../../data/models/cart_item.dart';
import '../../data/models/order.dart';
import '../../data/models/purchase_origin.dart';
import '../../state/cart_controller.dart';
import '../../state/origin_controller.dart';
import '../../state/order_controller.dart';
import '../../state/store_location_controller.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/primary_button.dart';
import 'cart_screen.dart';
import 'order_generated_screen.dart';

/// Resumen de la orden antes de generar el código.
///
/// Muestra productos, cantidades, precios, subtotales, total y el origen de la
/// compra. La orden **no** se marca como pagada: el pago se hace en caja.
class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  static const String routeName = '/summary';

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  bool _submitting = false;

  Future<void> _generateOrder() async {
    if (_submitting) return;
    final CartController cart = context.read<CartController>();
    final OriginController originController = context.read<OriginController>();
    final OrderController orders = context.read<OrderController>();
    final PurchaseOrigin? origin = originController.origin;

    if (cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tu carrito está vacío. Agrega productos primero.'),
        ),
      );
      return;
    }
    if (origin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona un origen de compra para continuar.'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    Order? order;
    try {
      order = await orders.createOrder(
        items: cart.items,
        origin: origin,
        storeId: context.read<StoreLocationController>().location.id,
      );
    } catch (error) {
      order = null;
      if (mounted) {
        // La orden NO se muestra como confirmada: el servidor no la guardó.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se pudo guardar la orden en el servidor. '
              'Revisa tu conexión e inténtalo de nuevo.',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }

    if (!mounted) return;
    setState(() => _submitting = false);

    if (order == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo generar la orden. Intenta de nuevo.'),
        ),
      );
      return;
    }

    // El carrito solo se borra después de que el pedido quedó guardado.
    await cart.clear();
    if (!mounted) return;
    await Navigator.of(context).pushReplacementNamed(
      OrderGeneratedScreen.routeName,
      arguments: OrderGeneratedArgs(order: order),
    );
  }

  @override
  Widget build(BuildContext context) {
    final CartController cart = context.watch<CartController>();
    final PurchaseOrigin? origin = context.watch<OriginController>().origin;
    final bool creating = context.watch<OrderController>().isCreating;
    final int productCount = cart.items.length;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppTopBar(
        title: 'Resumen de tu orden',
        titleStyle: AppText.body(25, weight: FontWeight.w600),
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double maxWidth = constraints.maxWidth >= 600 ? 620 : 460;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 17, 22, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: cart.isEmpty
                      ? EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'No hay nada que resumir',
                          message:
                              'Agrega productos al carrito para ver el resumen '
                              'de tu orden.',
                          actionLabel: 'Volver al carrito',
                          onAction: () => Navigator.of(context).maybePop(),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _OriginChip(origin: origin),
                            const SizedBox(height: 40),
                            Text(
                              '$productCount Productos',
                              style: AppText.body(19, weight: FontWeight.w600),
                            ),
                            const SizedBox(height: 10),
                            ...cart.items.map(
                              (CartItem item) => _SummaryRow(item: item),
                            ),
                            const Divider(height: 93),
                            _TotalLine(
                              label: 'Subtotal',
                              value: formatCop(cart.subtotal),
                            ),
                            if (cart.discount > 0) ...<Widget>[
                              const SizedBox(height: 8),
                              _TotalLine(
                                label: 'Descuentos',
                                value: '-${formatCop(cart.discount)}',
                                valueColor: AppColors.success,
                              ),
                            ],
                            const Divider(height: 101),
                            _TotalLine(
                              label: 'Total a pagar en caja',
                              value: formatCop(cart.total),
                              valueColor: AppColors.primary,
                              emphasize: true,
                            ),
                            const SizedBox(height: 62),
                            PrimaryButton(
                              label: 'Generar QR del pedido',
                              height: 65,
                              isLoading: _submitting || creating,
                              onPressed: _submitting || creating
                                  ? null
                                  : _generateOrder,
                            ),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(context)
                                      .pushNamed(CartScreen.routeName),
                              child: Text(
                                'Volver al carrito para corregir',
                                style: AppText.body(
                                  15,
                                  weight: FontWeight.w600,
                                  color: AppColors.muted,
                                ),
                              ),
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

/// Chip con el origen de la compra.
class _OriginChip extends StatelessWidget {
  const _OriginChip({required this.origin});

  final PurchaseOrigin? origin;

  @override
  Widget build(BuildContext context) {
    final PurchaseOrigin value = origin ?? PurchaseOrigin.inStore;
    return Align(
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10.5),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Image.asset(
              'assets/figma/icon_market.png',
              height: 26,
              width: 26,
              fit: BoxFit.contain,
              errorBuilder: (
                BuildContext context,
                Object error,
                StackTrace? stack,
              ) => const Icon(Icons.storefront, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 8),
            Text(
              value.summaryLabel,
              style: AppText.body(
                15,
                weight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila de producto del resumen.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              item.name,
              style: AppText.body(15, color: AppColors.muted),
            ),
          ),
          SizedBox(
            width: 82,
            child: Text(
              '${item.quantity}x${formatCop(item.unitPrice)}',
              textAlign: TextAlign.right,
              style: AppText.body(15, color: AppColors.muted),
            ),
          ),
          SizedBox(
            width: 82,
            child: Text(
              formatCop(item.payableTotal),
              textAlign: TextAlign.right,
              style: AppText.body(15, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalLine extends StatelessWidget {
  const _TotalLine({
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
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: AppText.body(emphasize ? 18 : 16, weight: FontWeight.w600),
          ),
        ),
        Text(
          value,
          style: AppText.body(
            emphasize ? 22 : 16,
            weight: FontWeight.w800,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
