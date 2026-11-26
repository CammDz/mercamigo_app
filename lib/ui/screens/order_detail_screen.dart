import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/app_date_time.dart';
import '../../core/utils/money.dart';
import '../../data/models/order.dart';
import '../../repositories/order_repository.dart';
import '../../services/order_code_service.dart';
import '../../state/order_controller.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/order_qr.dart';
import '../widgets/order_expiry_countdown.dart';
import '../widgets/primary_button.dart';

/// Argumentos de la pantalla de detalle del pedido.
class OrderDetailArgs {
  const OrderDetailArgs({required this.order});

  final Order order;
}

/// Detalle de un pedido del historial.
///
/// Los productos, cantidades y precios son los que quedaron guardados en
/// `detalle_pedido` al confirmar la orden: no se recalculan con el catálogo
/// actual.
class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.order});

  static const String routeName = '/order-detail';

  final Order order;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late Order _order = widget.order;
  bool _busy = false;
  String? _message;

  Future<void> _share() async {
    await Clipboard.setData(
      ClipboardData(text: const OrderCodeService().buildShareText(_order)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Datos de la orden copiados al portapapeles.'),
      ),
    );
  }

  /// Cancela un pedido pendiente de pago.
  ///
  /// El servidor decide: si ya caducó o ya se pagó, devuelve el estado real y
  /// aquí solo se muestra el mensaje. Nunca se simula un reembolso.
  Future<void> _cancel() async {
    if (_busy) return;
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('¿Cancelar este pedido?'),
            content: const Text(
              'El pedido quedará cancelado y no se podrá cobrar. '
              'No se realizó ningún cobro.\n\n'
              'Los productos no vuelven al carrito automáticamente.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Volver'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                child: const Text('Sí, cancelar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final CancelOrderResult result = await context
          .read<OrderController>()
          .cancelOrder(_order);
      if (!mounted) return;
      setState(() {
        _order = _order.copyWith(
          status: result.status,
          clearExpiresAt: result.status != OrderStatus.pendingPayment,
        );
        _message = result.message;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _message = 'No se pudo cancelar: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // El código solo se muestra mientras la orden se puede cobrar o retirar.
    final bool canUseCode =
        !_order.isExpired &&
        (_order.status == OrderStatus.pendingPayment ||
            _order.status == OrderStatus.paid);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppTopBar(
        title: 'Orden ${_order.orderNumber}',
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _InfoCard(order: _order),
                      const SizedBox(height: 14),
                      _ItemsCard(order: _order),
                      const SizedBox(height: 14),
                      _TotalsCard(order: _order),
                      const SizedBox(height: 14),
                      _CodeCard(
                        order: _order,
                        canUseCode: canUseCode,
                        busy: _busy,
                        onShare: _share,
                        onCancel: _cancel,
                      ),
                      if (_message != null) ...<Widget>[
                        const SizedBox(height: 12),
                        Text(
                          _message!,
                          textAlign: TextAlign.center,
                          style: AppText.body(13, color: AppColors.muted),
                        ),
                      ],
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

/// Datos generales del pedido.
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    // La fecha se muestra en hora de Bogota, sin depender del telefono.
    final String date = formatBogotaDateTime(order.createdAt);
    final String expires = order.expiresAt == null
        ? ''
        : formatBogotaDateTime(order.expiresAt!);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Orden ${order.orderNumber}',
                  style: AppText.body(
                    19,
                    weight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
              Text(
                order.status.label,
                style: AppText.body(13, weight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Line(label: 'Fecha', value: date),
          if (expires.isNotEmpty) _Line(label: 'Vence', value: expires),
          _Line(label: 'Origen', value: order.origin.label),
          _Line(
            label: 'Tienda',
            value: order.storeId == null
                ? 'Tienda de la app'
                : 'Tienda registrada',
          ),
          const SizedBox(height: 8),
          OrderExpiryCountdown(order: order),
        ],
      ),
    );
  }
}

/// Productos del pedido (datos históricos).
class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Productos (${order.totalUnits})',
            style: AppText.body(16, weight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ...order.items.map(
            (OrderItem item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      item.name,
                      style: AppText.body(14, color: AppColors.muted),
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      '${item.quantity}x${formatCop(item.unitPrice)}',
                      textAlign: TextAlign.right,
                      style: AppText.body(14, color: AppColors.muted),
                    ),
                  ),
                  SizedBox(
                    width: 92,
                    child: Text(
                      formatCop(item.subtotal ?? item.payableTotal),
                      textAlign: TextAlign.right,
                      style: AppText.body(14, weight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Totales del pedido.
class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text('Subtotal', style: AppText.body(15))),
              Text(
                formatCop(order.subtotal),
                style: AppText.body(15, weight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Total a pagar en caja',
                  style: AppText.body(16, weight: FontWeight.w600),
                ),
              ),
              Text(
                formatCop(order.total),
                style: AppText.body(
                  20,
                  weight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Código de barras de la orden y acciones del comprador.
class _CodeCard extends StatelessWidget {
  const _CodeCard({
    required this.order,
    required this.canUseCode,
    required this.busy,
    required this.onShare,
    required this.onCancel,
  });

  final Order order;
  final bool canUseCode;
  final bool busy;
  final VoidCallback onShare;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final bool canCancel =
        order.status == OrderStatus.pendingPayment && !order.isExpired;

    return _Card(
      child: Column(
        children: <Widget>[
          Text(
            'Código QR de la orden',
            style: AppText.body(16, weight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (canUseCode)
            Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.grayBorder),
                ),
                child: OrderQr(order: order, size: 160),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'Este pedido ya no admite el código de cobro '
                '(estado: ${order.status.label}).',
                style: AppText.body(13, color: AppColors.muted),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'El número visible y el código QR identifican el mismo pedido.',
            textAlign: TextAlign.center,
            style: AppText.body(12.5, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          PrimaryButton.outlined(
            label: order.isExpired ? 'Orden expirada' : 'Copiar datos',
            icon: order.isExpired
                ? Icons.timer_off_outlined
                : Icons.copy_all_outlined,
            onPressed: order.isExpired ? null : onShare,
          ),
          if (canCancel) ...<Widget>[
            const SizedBox(height: 10),
            PrimaryButton.outlined(
              label: 'Cancelar pedido',
              icon: Icons.cancel_outlined,
              isLoading: busy,
              onPressed: busy ? null : onCancel,
            ),
          ],
        ],
      ),
    );
  }
}

/// Tarjeta blanca con borde, del estilo del prototipo.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: child,
    );
  }
}

/// Fila etiqueta / valor.
class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: AppText.body(13.5, color: AppColors.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppText.body(14, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
