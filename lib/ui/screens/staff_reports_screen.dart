import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/app_date_time.dart';
import '../../core/utils/money.dart';
import '../../data/models/staff_order.dart';
import '../../repositories/staff_repository.dart';
import '../widgets/figma_bottom_nav.dart';
import '../widgets/figma_header.dart';

/// Periodo de los reportes.
enum ReportPeriod {
  today('Hoy'),
  week('Semana'),
  month('Mes');

  const ReportPeriod(this.label);

  final String label;
}

/// Reportes de ventas reales de la caja.
///
/// Los calcula el servidor (`reporte_ventas`) con límites en
/// `America/Bogota` y contando cada pedido **una sola vez** por su estado
/// actual (`pagado` o `entregado`). La app solo muestra lo que recibe: no hay
/// cifras fijas ni porcentajes inventados.
class StaffReportsScreen extends StatefulWidget {
  const StaffReportsScreen({super.key});

  static const String routeName = '/caja/reportes';

  @override
  State<StaffReportsScreen> createState() => _StaffReportsScreenState();
}

class _StaffReportsScreenState extends State<StaffReportsScreen> {
  ReportPeriod _period = ReportPeriod.today;
  int _requestId = 0;

  SalesReport? _report;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Límites del periodo en hora de Bogotá (solo fechas de calendario).
  ({DateTime from, DateTime to}) _range() {
    final DateTime now = toBogota(DateTime.now());
    final DateTime day = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case ReportPeriod.today:
        return (from: day, to: day);
      case ReportPeriod.week:
        return (from: day.subtract(const Duration(days: 6)), to: day);
      case ReportPeriod.month:
        return (from: DateTime(day.year, day.month, 1), to: day);
    }
  }

  Future<void> _load() async {
    final int request = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ({DateTime from, DateTime to}) range = _range();
      final SalesReport report =
          await context.read<StaffRepository>().salesReport(
                from: range.from,
                to: range.to,
              );
      if (!mounted || request != _requestId) return;
      setState(() {
        _report = report;
        _loading = false;
      });
    } on StaffException catch (error) {
      if (!mounted || request != _requestId) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _requestId) return;
      setState(() {
        _error = 'No se pudo cargar el reporte: $error';
        _loading = false;
      });
    }
  }

  void _changePeriod(ReportPeriod period) {
    if (period == _period) return;
    setState(() => _period = period);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: FigmaHeader(
        title: 'REPORTES',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Expanded(child: _body()),
            const StaffBottomNav(currentIndex: 2),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
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
                _error!,
                textAlign: TextAlign.center,
                style: AppText.body(14, color: AppColors.danger),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final SalesReport report = _report!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        children: <Widget>[
          Text(
            'Resumen de ventas',
            style: AppText.body(17, weight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            'Consulta el rendimiento de tus compras',
            style: AppText.body(12.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),
          const FigmaLabel('Periodo'),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              for (final ReportPeriod period in ReportPeriod.values) ...<Widget>[
                if (period != ReportPeriod.values.first)
                  const SizedBox(width: 8),
                Expanded(
                  child: FigmaChip(
                    label: period.label,
                    selected: _period == period,
                    onTap: () => _changePeriod(period),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          _TotalCard(report: report, period: _period),
          const SizedBox(height: 18),
          Text(
            'Ventas por día',
            style: AppText.body(15, weight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _SalesChart(points: report.points),
          const SizedBox(height: 16),
          _TopProductsCard(products: report.topProducts),
          const SizedBox(height: 12),
          Text(
            'Periodo consultado: ${formatCalendarDate(report.from)} '
            'a ${formatCalendarDate(report.to)}.',
            style: AppText.body(11.5, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta azul con las ventas totales del periodo.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.report, required this.period});

  final SalesReport report;
  final ReportPeriod period;

  @override
  Widget build(BuildContext context) {
    final String label = switch (period) {
      ReportPeriod.today => 'VENTAS TOTALES DEL DÍA',
      ReportPeriod.week => 'VENTAS TOTALES DE LA SEMANA',
      ReportPeriod.month => 'VENTAS TOTALES DEL MES',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: AppText.body(
              11,
              weight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.9),
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            formatCop(report.totalSales),
            style: AppText.body(
              26,
              weight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${report.totalOrders} '
            '${report.totalOrders == 1 ? 'pedido' : 'pedidos'} · '
            'Ticket promedio ${formatCop(report.averageTicket)}',
            style: AppText.body(
              11.5,
              weight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Gráfico de barras de ventas por día.
class _SalesChart extends StatelessWidget {
  const _SalesChart({required this.points});

  final List<SalesReportPoint> points;

  static const List<String> _weekdays = <String>[
    'Lun',
    'Mar',
    'Mié',
    'Jue',
    'Vie',
    'Sáb',
    'Dom',
  ];

  @override
  Widget build(BuildContext context) {
    final int maxSales = points.fold<int>(
      0,
      (int max, SalesReportPoint point) =>
          point.sales > max ? point.sales : max,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.lilacSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.textDark, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Consulta el rendimiento de tus compras',
            style: AppText.body(11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          if (points.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Center(
                child: Text(
                  'Todavía no hay ventas en este periodo.',
                  style: AppText.body(12.5, color: AppColors.textMuted),
                ),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                SizedBox(
                  width: 46,
                  height: 150,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      _axis(maxSales),
                      _axis(maxSales ~/ 2),
                      const Text(r'$0', style: TextStyle(fontSize: 9)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SizedBox(
                    height: 150,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          for (final SalesReportPoint point in points)
                            _Bar(
                              label: _weekdays[point.date.weekday - 1],
                              height: maxSales == 0
                                  ? 4
                                  : (point.sales / maxSales) * 130,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _axis(int value) {
    return Text(
      '\$${value >= 1000 ? '${(value / 1000).round()}k' : value}',
      style: const TextStyle(fontSize: 9),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.height});

  final String label;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          Container(
            width: 22,
            height: height.clamp(4, 130),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 9)),
        ],
      ),
    );
  }
}

/// Tarjeta azul con los productos más vendidos.
class _TopProductsCard extends StatelessWidget {
  const _TopProductsCard({required this.products});

  final List<TopProduct> products;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'PRODUCTOS MÁS VENDIDOS',
            style: AppText.body(
              10.5,
              weight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.9),
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          if (products.isEmpty)
            Text(
              'Sin productos vendidos en este periodo.',
              style: AppText.body(12, color: Colors.white),
            )
          else
            for (int i = 0; i < products.length && i < 5; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 18,
                      child: Text(
                        '${i + 1}',
                        style: AppText.body(
                          12,
                          weight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        products[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(12.5, color: Colors.white),
                      ),
                    ),
                    Text(
                      '${products[i].units} '
                      '${products[i].units == 1 ? 'unidad' : 'unidades'}',
                      style: AppText.body(
                        11.5,
                        weight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
