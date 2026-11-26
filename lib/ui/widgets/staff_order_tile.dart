import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/app_date_time.dart';
import '../../core/utils/money.dart';
import '../../data/models/order.dart';
import '../../data/models/staff_order.dart';

/// Color e ícono del estado de un pedido.
Color staffStatusColor(OrderStatus status) {
  return switch (status) {
    OrderStatus.pendingPayment => AppColors.warning,
    OrderStatus.paid => AppColors.primary,
    OrderStatus.delivered => AppColors.success,
    OrderStatus.cancelled => AppColors.muted,
    OrderStatus.expired => AppColors.danger,
  };
}

IconData staffStatusIcon(OrderStatus status) {
  return switch (status) {
    OrderStatus.pendingPayment => Icons.schedule_outlined,
    OrderStatus.paid => Icons.payments_outlined,
    OrderStatus.delivered => Icons.inventory_2_outlined,
    OrderStatus.cancelled => Icons.cancel_outlined,
    OrderStatus.expired => Icons.timer_off_outlined,
  };
}

/// Etiqueta corta del estado, como en el diseño de caja.
String staffStatusLabel(OrderStatus status) {
  return switch (status) {
    OrderStatus.pendingPayment => 'EN TIENDA',
    OrderStatus.paid => 'PAGADO',
    OrderStatus.delivered => 'ENTREGADO',
    OrderStatus.cancelled => 'CANCELADA',
    OrderStatus.expired => 'EXPIRADO',
  };
}

/// Distintivo compacto del estado de un pedido.
///
/// Usa los colores del rediseño: lila para "en tienda", verde claro para
/// "entregado" y rojo claro para "cancelada".
class StaffStatusPill extends StatelessWidget {
  const StaffStatusPill({super.key, required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color foreground) = switch (status) {
      OrderStatus.pendingPayment => (AppColors.lilac, AppColors.textDark),
      OrderStatus.paid => (AppColors.primary, Colors.white),
      OrderStatus.delivered => (AppColors.successSoft, AppColors.textDark),
      OrderStatus.cancelled => (AppColors.dangerSoft, AppColors.textDark),
      OrderStatus.expired => (AppColors.dangerSoft, AppColors.textDark),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        staffStatusLabel(status),
        style: AppText.body(
          10.5,
          weight: FontWeight.w700,
          color: foreground,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Fila de un pedido en las listas de caja.
///
/// Reproduce la fila del diseño: número y unidades a la izquierda, estado en
/// el centro y hora + total a la derecha, separada por una línea fina.
class StaffOrderTile extends StatelessWidget {
  const StaffOrderTile({
    super.key,
    required this.order,
    required this.onTap,
    this.showDetailHint = false,
  });

  final StaffOrderSummary order;
  final VoidCallback onTap;

  /// Muestra "Ver detalle" debajo del total (historial).
  final bool showDetailHint;

  @override
  Widget build(BuildContext context) {
    final String units =
        '${order.units} ${order.units == 1 ? 'artículo' : 'artículos'}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      order.orderNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(
                        19,
                        weight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      units,
                      style: AppText.body(12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Center(child: StaffStatusPill(status: order.status)),
              ),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      formatRelativeTime(order.createdAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(11, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatCop(order.total),
                      style: AppText.body(
                        15,
                        weight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    if (showDetailHint) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        'Ver detalle',
                        style: AppText.body(
                          11,
                          weight: FontWeight.w500,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
