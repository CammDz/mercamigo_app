import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/app_date_time.dart';
import '../../data/models/order.dart';
import 'order_qr.dart';

/// Tarjeta compacta del pedido para compartir como imagen.
class OrderShareCard extends StatelessWidget {
  const OrderShareCard({
    super.key,
    required this.order,
    required this.storeName,
  });

  final Order order;
  final String storeName;

  static const double width = 320;

  @override
  Widget build(BuildContext context) {
    final DateTime? expiresAt = order.expiresAt;
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Image.asset(
            'assets/figma/logo.png',
            width: 58,
            height: 52,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 4),
          Text(
            storeName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(13, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          Text(
            'ORDEN',
            style: AppText.body(
              12,
              color: AppColors.muted,
              weight: FontWeight.w700,
            ),
          ),
          Text(
            '#${order.orderNumber}',
            style: AppText.display(32, weight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: OrderQr(order: order, size: 194),
          ),
          const SizedBox(height: 12),
          Text(
            'Muestra este QR en caja o indica el número de orden.',
            textAlign: TextAlign.center,
            style: AppText.body(13, color: AppColors.muted),
          ),
          if (expiresAt != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              'Vence: ${formatBogotaDateTime(expiresAt)}',
              style: AppText.body(12, color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}
