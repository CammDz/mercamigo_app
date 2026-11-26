import 'package:flutter/foundation.dart';

import '../data/models/purchase_origin.dart';
import '../repositories/cart_repository.dart';

/// Estado del origen de compra.
///
/// El origen se elige una sola vez ("Estoy en la tienda" o "Pedir desde donde
/// estés"), se conserva durante todo el recorrido y se guarda junto al pedido.
/// Nunca se cambia automáticamente por GPS.
class OriginController extends ChangeNotifier {
  OriginController({required this.cartRepository});

  final CartRepository cartRepository;

  PurchaseOrigin? _origin;

  /// Origen actual (null si todavía no se eligió).
  PurchaseOrigin? get origin => _origin;

  bool get hasOrigin => _origin != null;

  /// Restaura el origen guardado localmente.
  Future<void> load() async {
    _origin = await cartRepository.loadOrigin();
    notifyListeners();
  }

  /// Fija y persiste el origen de compra.
  Future<void> setOrigin(PurchaseOrigin origin) async {
    if (_origin == origin) return;
    _origin = origin;
    notifyListeners();
    await cartRepository.saveOrigin(origin);
  }

  /// Borra el origen (solo se usa al reiniciar el recorrido).
  Future<void> clear() async {
    _origin = null;
    notifyListeners();
    await cartRepository.saveOrigin(PurchaseOrigin.inStore);
  }
}
