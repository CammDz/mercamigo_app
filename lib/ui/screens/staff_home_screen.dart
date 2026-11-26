import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/order.dart';
import '../../data/models/staff_order.dart';
import '../../repositories/staff_repository.dart';
import '../../services/auth_service.dart';
import '../widgets/figma_bottom_nav.dart';
import '../widgets/figma_header.dart';
import '../widgets/staff_orders_body.dart';
import 'staff_order_detail_screen.dart';
import 'staff_scanner_screen.dart';

/// Inicio del **personal de caja**.
///
/// Muestra los pedidos pendientes de pago, los pagados pendientes de entrega
/// y los completados. El rol se comprobó en el servidor; cada acción se vuelve
/// a comprobar allí.
class StaffHomeScreen extends StatefulWidget {
  const StaffHomeScreen({super.key});

  static const String routeName = '/caja';

  @override
  State<StaffHomeScreen> createState() => _StaffHomeScreenState();
}

class _StaffHomeScreenState extends State<StaffHomeScreen> {
  int _tab = 0;
  bool _signingOut = false;
  final List<int?> _counts = <int?>[null, null, null];

  static const List<List<OrderStatus>> _filters = <List<OrderStatus>>[
    <OrderStatus>[OrderStatus.pendingPayment],
    <OrderStatus>[OrderStatus.paid],
    <OrderStatus>[OrderStatus.delivered],
  ];

  static const List<String> _labels = <String>[
    'Pendientes',
    'En proceso',
    'Completados',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCounts());
  }

  Future<void> _loadCounts() async {
    final StaffRepository repository = context.read<StaffRepository>();
    for (int i = 0; i < _filters.length; i++) {
      try {
        final StaffOrderPage page = await repository.listOrders(
          statuses: _filters[i],
        );
        if (!mounted) return;
        setState(() => _counts[i] = page.total);
      } catch (_) {
        // El contador es informativo: si falla, la lista sigue funcionando.
      }
    }
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('¿Cerrar sesión?'),
            content: const Text(
              'Se cerrará la sesión de caja en este dispositivo.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Cerrar sesión'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _signingOut = true);
    await context.read<AuthService>().signOut();
    if (!mounted) return;
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
  }

  Future<void> _openScanner() async {
    final StaffOrderDetail? order = await Navigator.of(context)
        .push<StaffOrderDetail>(
          MaterialPageRoute<StaffOrderDetail>(
            fullscreenDialog: true,
            builder: (BuildContext context) => const StaffScannerScreen(),
          ),
        );
    if (order != null && mounted) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              StaffOrderDetailScreen(initial: order),
        ),
      );
      if (mounted) {
        setState(() => _counts[_tab] = null);
        _loadCounts();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AuthService auth = context.watch<AuthService>();
    if (!auth.isPersonal) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: FigmaHeader(
          title: 'CAJA',
          onBack: () => Navigator.of(context).maybePop(),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.lock_outline,
                  size: 46,
                  color: AppColors.textMuted,
                ),
                const SizedBox(height: 12),
                Text(
                  'Tu cuenta no tiene el rol de personal de caja. '
                  'El permiso se comprueba en el servidor.',
                  textAlign: TextAlign.center,
                  style: AppText.body(15, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: FigmaHeader(
        title: 'ÓRDENES PENDIENTES',
        actions: <Widget>[
          IconButton(
            onPressed: _signingOut ? null : _signOut,
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout, color: Colors.white, size: 21),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: <Widget>[
                  for (int i = 0; i < _labels.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: FigmaChip(
                        label: _labels[i],
                        count: _counts[i],
                        selected: _tab == i,
                        onTap: () {
                          if (_tab == i) return;
                          setState(() => _tab = i);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: StaffOrdersBody(
                key: ValueKey<int>(_tab),
                statuses: _filters[_tab],
                showSearch: false,
                showScan: false,
                emptyMessage: switch (_tab) {
                  0 => 'No hay pedidos pendientes de pago.',
                  1 => 'No hay pedidos pagados pendientes de entrega.',
                  _ => 'Todavía no hay pedidos completados.',
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _openScanner,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.qr_code_scanner, size: 22),
                  label: Text(
                    'Escanear nuevo pedido',
                    style: AppText.body(15, weight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            const StaffBottomNav(currentIndex: 0),
          ],
        ),
      ),
    );
  }
}
