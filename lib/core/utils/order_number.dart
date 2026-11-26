/// Formato del número visible de la orden.
///
/// El consecutivo **lo genera la base de datos**: `pedidos.numero_orden` es
/// una columna IDENTITY, así que la app no inventa números ni aleatorios.
///
/// Aquí solo se le da formato para que el número sea legible y siempre igual
/// en todas las pantallas:
///
///     MCA-000104
///
/// · El prefijo `MCA` identifica a Mercamigo.
/// · El número se rellena con ceros a la izquierda hasta 6 dígitos, pero
///   **sin truncar**: si la base llega a 1.000.000, se muestra MCA-1000000.
///
/// Este número identifica la orden para el comprador y el personal de caja.
/// El código de barras de la orden representa **este mismo número**; la
/// autorización para cobrar o entregar la decide el servidor por el rol de
/// caja, nunca el número por sí solo.
library;

/// Prefijo del número visible de la orden.
const String orderNumberPrefix = 'MCA';

/// Mínimo de dígitos del número visible (con ceros a la izquierda).
const int orderNumberMinDigits = 6;

/// Formatea el consecutivo de la base de datos como número visible.
///
/// [numero] es `pedidos.numero_orden`.
String formatOrderNumber(int numero) {
  final String digits = numero.toString();
  final String padded = digits.length >= orderNumberMinDigits
      ? digits
      : digits.padLeft(orderNumberMinDigits, '0');
  return '$orderNumberPrefix-$padded';
}

/// Extrae el consecutivo de un número visible con formato.
///
/// Devuelve `null` si el texto no tiene el formato esperado.
int? parseOrderNumber(String orderNumber) {
  final int dash = orderNumber.lastIndexOf('-');
  if (dash < 0 || dash == orderNumber.length - 1) return null;
  return int.tryParse(orderNumber.substring(dash + 1));
}
