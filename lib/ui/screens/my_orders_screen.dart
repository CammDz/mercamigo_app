import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/app_date_time.dart';
import '../../core/utils/money.dart';
import '../../data/models/order.dart';
import '../../data/models/product.dart';
import '../../repositories/catalog_repository.dart';
import '../../state/cart_controller.dart';
import '../../services/auth_service.dart';
import '../../state/order_history_controller.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/primary_button.dart';
import 'cart_screen.dart';
import 'order_detail_screen.dart';

/// Historial de pedidos del usuario autenticado.
///
/// Consulta `pedidos` del usuario de la sesión (la política `pedidos_propios`
/// ya lo restringe) con paginación y estados de carga, vacío y error.
class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  static const String routeName = '/orders';

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final double position = _scrollController.position.pixels;
    final double max = _scrollController.position.maxScrollExtent;
    if (position >= max - 220) _loadMore();
  }

  Future<void> _load() async {
    final String? userId = context.read<AuthService>().userId;
    if (userId == null) return;
    await context.read<OrderHistoryController>().load(userId, refresh: true);
  }

  Future<void> _loadMore() async {
    final String? userId = context.read<AuthService>().userId;
    if (userId == null) return;
    await context.read<OrderHistoryController>().loadMore(userId);
  }

  /// Vuelve a comprar los productos de una orden caducada.
  ///
  /// Se crea una **orden nueva** con los productos que siguen disponibles y
  /// con los precios de ahora: la orden caducada no se reactiva ni se
  /// prolonga.
  Future<void> _buyAgain(BuildContext context, Order order) async {
    final CatalogRepository catalog = context.read<CatalogRepository>();
    final CartController cart = context.read<CartController>();

    int agregados = 0;
    int noDisponibles = 0;
    for (final OrderItem item in order.items) {
      final Product? product = catalog.byId(item.productId);
      if (product == null || !product.isActive) {
        noDisponibles++;
        continue;
      }
      await cart.add(product, quantity: item.quantity);
      agregados++;
    }

    if (!context.mounted) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (agregados == 0) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Ninguno de los productos sigue disponible.'),
        ),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          noDisponibles == 0
              ? 'Productos añadidos al carrito.'
              : 'Productos añadidos al carrito. '
                  '$noDisponibles ya no están disponibles.',
        ),
      ),
    );
    await Navigator.of(context).pushNamed(CartScreen.routeName);
  }

  @override
  Widget build(BuildContext context) {
    final OrderHistoryController history = context.watch<OrderHistoryController>();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppTopBar(
        title: 'Mis pedidos',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            if (history.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.error_outline,
                          size: 18, color: AppColors.danger),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          history.error!,
                          style: AppText.body(13, color: AppColors.danger),
                        ),
                      ),
                      TextButton(
                        onPressed: _load,
                        child: Text(
                          'Reintentar',
                          style: AppText.body(13, weight: FontWeight.w700,
                              color: AppColors.danger),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Builder(
                builder: (BuildContext context) {
                  if (history.isLoading && history.orders.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (history.isEmpty) {
                    return EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'Todavía no tienes pedidos',
                      message:
                          'Cuando hagas una compra, aquí verás el número de '
                          'orden, la fecha, el total y el estado.',
                      actionLabel: 'Actualizar',
                      onAction: _load,
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
                      itemCount: history.orders.length + 1,
                      separatorBuilder: (_, int _) => const SizedBox(height: 12),
                      itemBuilder: (BuildContext context, int index) {
                        if (index == history.orders.length) {
                          if (history.isLoadingMore) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 18),
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          if (!history.hasMore) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Text(
                                'No hay más pedidos.',
                                textAlign: TextAlign.center,
                                style:
                                    AppText.body(12.5, color: AppColors.muted),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        }
                        final Order order = history.orders[index];
                        return _OrderCard(
                          order: order,
                          onTap: () => Navigator.of(context).pushNamed(
                            OrderDetailScreen.routeName,
                            arguments: OrderDetailArgs(order: order),
                          ),
                          onBuyAgain: () => _buyAgain(context, order),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de un pedido del historial.
class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.onTap,
    required this.onBuyAgain,
  });

  final Order order;
  final VoidCallback onTap;

  /// Vuelve a comprar los productos de una orden caducada.
  final VoidCallback onBuyAgain;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Orden ${order.orderNumber}',
                      style: AppText.body(17, weight: FontWeight.w800,
                          color: AppColors.primary),
                    ),
                  ),
                  _StatusPill(status: order.status),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _formatDate(order.createdAt),
                style: AppText.body(13, color: AppColors.muted),
              ),
              const SizedBox(height: 4),
              Text(
                order.origin.label,
                style: AppText.body(13.5, color: AppColors.muted),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${order.totalUnits} producto(s)',
                      style: AppText.body(13.5, color: AppColors.muted),
                    ),
                  ),
                  Text(
                    formatCop(order.total),
                    style: AppText.body(18, weight: FontWeight.w800),
                  ),
                ],
              ),
              if (order.status == OrderStatus.expired ||
                  order.isExpired) ...<Widget>[
                const SizedBox(height: 10),
                // La orden caducada se conserva en el historial y se ofrece
                // rehacerla como una orden nueva.
                Text(
                  'Esta orden caducó. Puedes volver a comprar sus productos.',
                  style: AppText.body(12.5, color: AppColors.warning),
                ),
                const SizedBox(height: 8),
                PrimaryButton.outlined(
                  label: 'Volver a comprar',
                  icon: Icons.refresh,
                  height: 44,
                  onPressed: onBuyAgain,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Fecha y hora de la orden, siempre en hora de Bogota.
  static String _formatDate(DateTime date) => formatBogotaDateTime(date);
}

/// Distintivo del estado del pedido.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (status) {
      OrderStatus.pendingPayment => AppColors.warning,
      OrderStatus.paid => AppColors.primary,
      OrderStatus.delivered => AppColors.success,
      OrderStatus.cancelled => AppColors.danger,
      OrderStatus.expired => AppColors.muted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: AppText.body(12, weight: FontWeight.w700, color: color),
      ),
    );
  }
}
