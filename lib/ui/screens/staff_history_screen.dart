import 'package:flutter/material.dart';

import '../../data/models/order.dart';
import '../widgets/figma_bottom_nav.dart';
import '../widgets/figma_header.dart';
import '../widgets/staff_orders_body.dart';

/// Historial de pedidos de la caja con filtros por estado.
///
/// Los filtros se aplican en el servidor; la búsqueda acepta el número de
/// orden o el nombre del cliente. El recibo conserva los precios históricos.
class StaffHistoryScreen extends StatefulWidget {
  const StaffHistoryScreen({super.key});

  static const String routeName = '/caja/historial';

  @override
  State<StaffHistoryScreen> createState() => _StaffHistoryScreenState();
}

class _StaffHistoryScreenState extends State<StaffHistoryScreen> {
  String _filter = 'todos';

  static const Map<String, List<OrderStatus>?> _filters =
      <String, List<OrderStatus>?>{
        'todos': null,
        'pendiente_pago': <OrderStatus>[OrderStatus.pendingPayment],
        'pagado': <OrderStatus>[OrderStatus.paid],
        'entregado': <OrderStatus>[OrderStatus.delivered],
        'cancelado': <OrderStatus>[OrderStatus.cancelled],
        'expirado': <OrderStatus>[OrderStatus.expired],
      };

  static const Map<String, String> _labels = <String, String>{
    'todos': 'Todas',
    'pendiente_pago': 'Pendientes',
    'pagado': 'Pagados',
    'entregado': 'Entregadas',
    'cancelado': 'Canceladas',
    'expirado': 'Expiradas',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: FigmaHeader(
        title: 'HISTORIAL DE ÓRDENES',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: StaffOrdersBody(
                key: ValueKey<String>(_filter),
                statuses: _filters[_filter],
                searchLabel: 'Buscar Órdenes',
                searchHint: 'Buscar por número de orden…',
                showScan: false,
                showDetailHint: true,
                emptyMessage:
                    'No hay pedidos con el filtro "${_labels[_filter]}".',
                filterBar: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
                      child: FigmaLabel('Filtrar por estado'),
                    ),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        children: <Widget>[
                          for (final String key in _filters.keys) ...<Widget>[
                            if (key != _filters.keys.first)
                              const SizedBox(width: 8),
                            FigmaChip(
                              label: _labels[key] ?? key,
                              selected: _filter == key,
                              onTap: () => setState(() => _filter = key),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 14, 20, 2),
                      child: FigmaLabel('Órdenes Recientes'),
                    ),
                  ],
                ),
              ),
            ),
            const StaffBottomNav(currentIndex: 1),
          ],
        ),
      ),
    );
  }
}
