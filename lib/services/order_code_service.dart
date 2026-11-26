import 'package:intl/intl.dart';

import '../data/models/order.dart';

/// Texto de la orden para copiar o compartir.
///
/// El QR usa el identificador del pedido en el servidor (`pedidos.id`) cuando
/// existe; si no, el número visible. El número de orden se sigue mostrando en
/// pantalla para buscarlo a mano. No se incluyen tokens de sesión ni claves.
class OrderCodeService {
  const OrderCodeService();

  /// Contenido del código QR y del texto compartido.
  String buildOrderPayload(Order order) => order.qrPayload;

  /// Texto legible para el portapapeles o para compartir.
  String buildShareText(Order order) {
    final DateFormat date = DateFormat('dd/MM/yyyy HH:mm');
    final StringBuffer buffer = StringBuffer()
      ..writeln('MERCAMIGO')
      ..writeln('Orden: ${order.orderNumber}')
      ..writeln('Fecha: ${date.format(order.createdAtBogota)}')
      ..writeln('Origen: ${order.origin.label}')
      ..writeln('Estado: ${order.status.label}')
      ..writeln()
      ..writeln('Productos:');
    for (final OrderItem item in order.items) {
      buffer.writeln(
        '· ${item.quantity} x ${item.name} '
        '= ${item.payableTotal} COP',
      );
    }
    buffer
      ..writeln()
      ..writeln('Total a pagar en caja: ${order.total} COP');
    return buffer.toString();
  }
}
