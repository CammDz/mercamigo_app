import 'package:flutter/foundation.dart';

import '../data/models/order.dart';
import '../repositories/order_repository.dart';

/// Estado del historial de pedidos del usuario.
///
/// Permite paginar, y expone los estados de carga, vacío y error que pide
/// la pantalla "Mis pedidos".
class OrderHistoryController extends ChangeNotifier {
  OrderHistoryController({required this.repository});

  static const int pageSize = 15;

  final OrderRepository repository;

  final List<Order> _orders = <Order>[];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  /// Pedidos cargados hasta ahora.
  List<Order> get orders => List<Order>.unmodifiable(_orders);

  /// `true` mientras carga la primera página.
  bool get isLoading => _loading;

  /// `true` mientras carga la siguiente página.
  bool get isLoadingMore => _loadingMore;

  /// `true` si hay más páginas en el servidor.
  bool get hasMore => _hasMore;

  /// Mensaje de error de la última carga.
  String? get error => _error;

  /// `true` cuando ya se cargó y no hay pedidos.
  bool get isEmpty => !_loading && _error == null && _orders.isEmpty;

  /// Carga (o recarga) la primera página.
  Future<void> load(String userId, {bool refresh = false}) async {
    if (_loading) return;
    _loading = true;
    _error = null;
    if (refresh) {
      _orders.clear();
      _hasMore = true;
    }
    notifyListeners();

    try {
      final List<Order> page = await repository.loadServerOrders(
        userId: userId,
        page: 0,
        pageSize: pageSize,
      );
      _orders
        ..clear()
        ..addAll(page);
      _hasMore = page.length >= pageSize;
    } catch (error) {
      _error = '$error';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Carga la siguiente página.
  Future<void> loadMore(String userId) async {
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    notifyListeners();

    try {
      final int page = _orders.length ~/ pageSize;
      final List<Order> next = await repository.loadServerOrders(
        userId: userId,
        page: page,
        pageSize: pageSize,
      );
      _orders.addAll(next);
      _hasMore = next.length >= pageSize;
    } catch (error) {
      _error = '$error';
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  /// Limpia el historial en memoria (al cerrar sesión).
  void clear() {
    _orders.clear();
    _hasMore = true;
    _error = null;
    notifyListeners();
  }
}
