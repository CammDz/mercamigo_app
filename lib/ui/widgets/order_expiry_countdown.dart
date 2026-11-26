import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/order.dart';

/// Cuenta regresiva de la vigencia de una orden pendiente de pago.
///
/// El plazo lo fija el **servidor** (`pedidos.expira_en`): la app solo lo
/// cuenta y lo muestra, nunca lo recalcula. Al llegar a cero, la orden pasa a
/// estar expirada y se avisa con [onExpired] para que la pantalla deshabilite
/// compartir o usar el código de barras.
class OrderExpiryCountdown extends StatefulWidget {
  const OrderExpiryCountdown({
    super.key,
    required this.order,
    this.onExpired,
    this.showIcon = true,
    this.labelPrefix = 'Tu orden vence en',
    this.labelSuffix = '',
    this.fontSize = 15,
    this.iconSize = 18,
    this.multiline = false,
  });

  /// Orden a la que se le cuenta el tiempo.
  final Order order;

  /// Se llama una sola vez cuando la orden caduca.
  final VoidCallback? onExpired;

  /// Muestra el icono del reloj.
  final bool showIcon;
  final String labelPrefix;
  final String labelSuffix;
  final double fontSize;
  final double iconSize;
  final bool multiline;

  @override
  State<OrderExpiryCountdown> createState() => _OrderExpiryCountdownState();
}

class _OrderExpiryCountdownState extends State<OrderExpiryCountdown> {
  Timer? _ticker;
  bool _expiredNotified = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _tick();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    setState(() {});
    if (widget.order.isExpired && !_expiredNotified) {
      _expiredNotified = true;
      widget.onExpired?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Order order = widget.order;
    final bool expired = order.isExpired;
    final Duration? left = order.remaining;

    if (order.status != OrderStatus.pendingPayment && !expired) {
      // Las ordenes pagadas o entregadas no caducan.
      return const SizedBox.shrink();
    }

    final String label = expired
        ? 'Orden expirada'
        : '${widget.labelPrefix}${widget.multiline ? '\n' : ' '}'
              '${_format(left)}${widget.labelSuffix}';

    final Color color = expired ? AppColors.danger : AppColors.primary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (widget.showIcon) ...<Widget>[
          Icon(
            expired ? Icons.timer_off_outlined : Icons.schedule_outlined,
            size: widget.iconSize,
            color: color,
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            style: AppText.body(
              widget.fontSize,
              weight: FontWeight.w700,
              color: color,
            ),
            textAlign: widget.multiline ? TextAlign.center : TextAlign.start,
            maxLines: widget.multiline ? 2 : 1,
          ),
        ),
      ],
    );
  }

  /// Formato `mm:ss` (o `hh:mm:ss` si hace falta).
  static String _format(Duration? left) {
    if (left == null) return '--:--';
    final int hours = left.inHours;
    final int minutes = left.inMinutes.remainder(60);
    final int seconds = left.inSeconds.remainder(60);
    String two(int value) => value.toString().padLeft(2, '0');
    if (hours > 0) return '$hours:${two(minutes)}:${two(seconds)}';
    return '${two(minutes)}:${two(seconds)}';
  }
}
