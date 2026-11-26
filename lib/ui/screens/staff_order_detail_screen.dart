import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/app_date_time.dart';
import '../../core/utils/money.dart';
import '../../data/models/order.dart';
import '../../data/models/staff_order.dart';
import '../../repositories/staff_repository.dart';
import '../widgets/figma_header.dart';

/// Recibo del pedido para el personal de caja.
///
/// Muestra el nombre real del cliente, el origen, los productos y precios
/// históricos y el total en formato de tirilla. Separa explícitamente:
///
/// · **Cobrar** → `pendiente_pago` a `pagado`.
/// · **Entregar** → `pagado` a `entregado`.
///
/// Las dos transiciones las decide el servidor de forma atómica; la interfaz
/// solo las solicita y muestra el resultado. Nunca se entrega sin pagar.
class StaffOrderDetailScreen extends StatefulWidget {
  const StaffOrderDetailScreen({super.key, this.orderId, this.initial})
    : assert(orderId != null || initial != null);

  final String? orderId;
  final StaffOrderDetail? initial;

  @override
  State<StaffOrderDetailScreen> createState() => _StaffOrderDetailScreenState();
}

class _StaffOrderDetailScreenState extends State<StaffOrderDetailScreen> {
  StaffOrderDetail? _order;
  bool _loading = false;
  bool _busy = false;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    _order = widget.initial;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool showSpinner = true}) async {
    final String? id = _order?.id ?? widget.orderId;
    if (id == null) return;
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final StaffOrderDetail detail = await context
          .read<StaffRepository>()
          .orderDetail(id);
      if (!mounted) return;
      setState(() {
        _order = detail;
        _loading = false;
        _error = null;
      });
    } on StaffException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar el pedido: $error';
      });
    }
  }

  Future<void> _confirmPayment() async {
    final StaffOrderDetail? order = _order;
    if (order == null || _busy) return;
    final bool confirmed = await _ask(
      title: '¿Confirmar pago recibido?',
      body:
          'Confirma que recibiste ${formatCop(order.total)} en caja. '
          'El pedido quedará pagado y pendiente de la entrega física.',
      confirmLabel: 'Sí, recibí el pago',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final StaffActionOutcome outcome = await context
          .read<StaffRepository>()
          .confirmPayment(order.id);
      if (!mounted) return;
      setState(() {
        _order = order.copyWith(
          status: outcome.status,
          paidAt:
              outcome.status == OrderStatus.paid ||
                  outcome.status == OrderStatus.delivered
              ? DateTime.now().toUtc()
              : null,
        );
        _message = outcome.message;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(outcome.message)));
      await _load(showSpinner: false);
    } on StaffException catch (error) {
      if (!mounted) return;
      setState(() => _message = error.message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelivery() async {
    final StaffOrderDetail? order = _order;
    if (order == null || _busy) return;
    final bool confirmed = await _ask(
      title: '¿Confirmar entrega física?',
      body:
          'Confirma que entregaste los productos al cliente. '
          'El pedido quedará completado.',
      confirmLabel: 'Sí, entregado',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final StaffActionOutcome outcome = await context
          .read<StaffRepository>()
          .confirmDelivery(order.id);
      if (!mounted) return;
      setState(() {
        _order = order.copyWith(
          status: outcome.status,
          deliveredAt: outcome.status == OrderStatus.delivered
              ? DateTime.now().toUtc()
              : null,
        );
        _message = outcome.message;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(outcome.message)));
      await _load(showSpinner: false);
    } on StaffException catch (error) {
      if (!mounted) return;
      setState(() => _message = error.message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _ask({
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Volver'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _copyReceipt() async {
    final StaffOrderDetail? order = _order;
    if (order == null) return;
    final StringBuffer buffer = StringBuffer()
      ..writeln('MERCAMIGO')
      ..writeln('Orden: ${order.orderNumber}')
      ..writeln('Cliente: ${order.customerName}')
      ..writeln('Origen: ${order.origin.label}')
      ..writeln('Fecha: ${formatBogotaDateTime(order.createdAt)}')
      ..writeln('Estado: ${order.status.label}')
      ..writeln();
    for (final StaffOrderItem item in order.items) {
      buffer.writeln(
        '${item.quantity} x ${item.name} = ${formatCop(item.subtotal)}',
      );
    }
    buffer
      ..writeln()
      ..writeln('Total: ${formatCop(order.total)}');
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recibo copiado al portapapeles.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final StaffOrderDetail? order = _order;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: FigmaHeader(
        title: 'DETALLE DE ORDEN',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: SafeArea(
        top: false,
        child: _loading && order == null
            ? const Center(child: CircularProgressIndicator())
            : _error != null && order == null
            ? _ErrorView(message: _error!, onRetry: _load)
            : order == null
            ? const SizedBox.shrink()
            : RefreshIndicator(
                onRefresh: () => _load(showSpinner: false),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  children: <Widget>[
                    if (_error != null) ...<Widget>[
                      _Banner(message: _error!, color: AppColors.danger),
                      const SizedBox(height: 10),
                    ],
                    _Receipt(order: order),
                    if (_message != null) ...<Widget>[
                      const SizedBox(height: 12),
                      _Banner(message: _message!, color: AppColors.primary),
                    ],
                    const SizedBox(height: 24),
                    _actions(order),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        onPressed: _busy ? null : _copyReceipt,
                        icon: const Icon(
                          Icons.copy_all_outlined,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                        label: Text(
                          'Copiar recibo',
                          style: AppText.body(
                            13,
                            weight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _actions(StaffOrderDetail order) {
    final bool pending = order.status == OrderStatus.pendingPayment;
    final bool paid = order.status == OrderStatus.paid;
    final bool expired = order.isExpiredByClock;

    final String primaryLabel;
    final VoidCallback? primaryAction;
    if (pending && !expired) {
      primaryLabel = 'Cobrar';
      primaryAction = _busy ? null : _confirmPayment;
    } else if (paid) {
      primaryLabel = 'Entregar';
      primaryAction = _busy ? null : _confirmDelivery;
    } else {
      primaryLabel = order.status == OrderStatus.delivered
          ? 'Completado'
          : 'No disponible';
      primaryAction = null;
    }

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.lilac,
                    foregroundColor: AppColors.textDark,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Volver',
                    style: AppText.body(14, weight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: primaryAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.primary.withValues(
                      alpha: 0.45,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          primaryLabel,
                          style: AppText.body(15, weight: FontWeight.w600),
                        ),
                ),
              ),
            ),
          ],
        ),
        if (pending && expired) ...<Widget>[
          const SizedBox(height: 12),
          const _Banner(
            message:
                'Este pedido caducó y no se puede cobrar. '
                'El cliente debe generar uno nuevo.',
            color: AppColors.danger,
          ),
        ],
        if (pending && !expired) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            'Primero registra el pago. La entrega se habilita después.',
            textAlign: TextAlign.center,
            style: AppText.body(11.5, color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }
}

/// Recibo completo en formato de tirilla.
class _Receipt extends StatelessWidget {
  const _Receipt({required this.order});

  final StaffOrderDetail order;

  @override
  Widget build(BuildContext context) {
    final String customer = order.customerName.isEmpty
        ? 'Sin nombre registrado'
        : order.customerName;
    final String origin = order.origin.label;
    final String relative = formatRelativeTime(order.createdAt);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Image.asset(
              'assets/figma/logo.png',
              width: 72,
              height: 64,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'MERCAMIGO',
              style: AppText.display(
                22,
                weight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              order.status.label.toUpperCase(),
              style: AppText.body(
                10,
                weight: FontWeight.w600,
                color: AppColors.textMuted,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'ORDEN: ${order.orderNumber}',
            style: AppText.body(14, weight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Cliente: $customer',
            style: AppText.body(12.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 2),
          Text(
            '$relative · $origin',
            style: AppText.body(12.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 18),
          Text(
            'PRODUCTOS',
            style: AppText.body(
              10.5,
              weight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          for (final StaffOrderItem item in order.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.name,
                    style: AppText.body(13, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${item.quantity} x ${formatCop(item.unitPrice)}',
                          style: AppText.body(12.5, color: AppColors.textMuted),
                        ),
                      ),
                      Text(
                        formatCop(item.subtotal),
                        style: AppText.body(13, weight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (order.items.isEmpty)
            Text(
              'Sin productos registrados.',
              style: AppText.body(13, color: AppColors.textMuted),
            ),
          const Divider(height: 20, color: AppColors.cardBorder),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'TOTAL COP',
                  style: AppText.body(15, weight: FontWeight.w700),
                ),
              ),
              Text(
                formatCop(order.total),
                style: AppText.body(17, weight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${order.items.length} '
            '${order.items.length == 1 ? 'producto' : 'productos'} · '
            '${order.units} ${order.units == 1 ? 'unidad' : 'unidades'}',
            style: AppText.body(11.5, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.color});

  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: AppText.body(13, color: color),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function({bool showSpinner}) onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.cloud_off_outlined,
              size: 42,
              color: AppColors.danger,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppText.body(14, color: AppColors.danger),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
