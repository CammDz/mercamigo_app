import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/order.dart';
import '../../data/models/staff_order.dart';
import '../../repositories/staff_repository.dart';
import '../screens/staff_order_detail_screen.dart';
import '../screens/staff_scanner_screen.dart';
import 'staff_order_tile.dart';

/// Lista de pedidos de caja con búsqueda, carga, error y reintento.
///
/// El filtro de estados se recibe desde la pantalla que lo usa. Cambiar de
/// filtro crea una instancia nueva (`key`) para que la lista se recargue.
class StaffOrdersBody extends StatefulWidget {
  const StaffOrdersBody({
    super.key,
    required this.statuses,
    required this.emptyMessage,
    this.searchHint = 'Buscar por número o cliente',
    this.searchLabel,
    this.filterBar,
    this.showSearch = true,
    this.showScan = true,
    this.showDetailHint = false,
  });

  /// Estados que se piden al servidor (`null` = todos).
  final List<OrderStatus>? statuses;

  final String emptyMessage;
  final String searchHint;

  /// Etiqueta opcional encima del campo de búsqueda.
  final String? searchLabel;

  /// Controles opcionales (filtros) debajo del campo de búsqueda.
  final Widget? filterBar;

  final bool showSearch;
  final bool showScan;

  /// Muestra "Ver detalle" en cada fila (historial).
  final bool showDetailHint;

  @override
  State<StaffOrdersBody> createState() => _StaffOrdersBodyState();
}

class _StaffOrdersBodyState extends State<StaffOrdersBody> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  int _requestId = 0;

  List<StaffOrderSummary> _orders = const <StaffOrderSummary>[];
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      setState(() => _query = value.trim());
      _load();
    });
  }

  Future<void> _load({bool showSpinner = true}) async {
    final int request = ++_requestId;
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _error = null);
    }

    try {
      final StaffOrderPage page = await context
          .read<StaffRepository>()
          .listOrders(statuses: widget.statuses, query: _query);
      if (!mounted || request != _requestId) return;
      setState(() {
        _orders = page.orders;
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
        _error = 'No se pudieron cargar los pedidos: $error';
        _loading = false;
      });
    }
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
      if (mounted) _load(showSpinner: false);
    }
  }

  Future<void> _openOrder(StaffOrderSummary order) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            StaffOrderDetailScreen(orderId: order.id),
      ),
    );
    if (mounted) _load(showSpinner: false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        if (widget.showSearch) ...<Widget>[
          if (widget.searchLabel != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.searchLabel!,
                  style: AppText.body(
                    13,
                    weight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              widget.searchLabel == null ? 10 : 0,
              20,
              8,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onQueryChanged,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: widget.searchHint,
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AppColors.textMuted,
                      ),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: AppColors.textMuted,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                _onQueryChanged('');
                              },
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: AppColors.cardBorder,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: AppColors.cardBorder,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.primary),
                      ),
                    ),
                  ),
                ),
                if (widget.showScan) ...<Widget>[
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _openScanner,
                    tooltip: 'Escanear el código QR del pedido',
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (widget.filterBar != null) widget.filterBar!,
        Expanded(child: _content()),
      ],
    );
  }

  Widget _content() {
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
    if (_orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(showSpinner: false),
        child: ListView(
          children: <Widget>[
            const SizedBox(height: 70),
            Icon(
              _query.isEmpty
                  ? Icons.receipt_long_outlined
                  : Icons.search_off_outlined,
              size: 46,
              color: AppColors.muted,
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Text(
                _query.isEmpty
                    ? widget.emptyMessage
                    : 'Ningún pedido coincide con "$_query".',
                textAlign: TextAlign.center,
                style: AppText.body(14, color: AppColors.muted),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: false),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        itemCount: _orders.length,
        separatorBuilder: (_, _) => const SizedBox(height: 0),
        itemBuilder: (BuildContext context, int index) {
          final StaffOrderSummary order = _orders[index];
          return StaffOrderTile(
            order: order,
            showDetailHint: widget.showDetailHint,
            onTap: () => _openOrder(order),
          );
        },
      ),
    );
  }
}
