import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/order.dart';

/// Código QR de una orden.
///
/// El contenido es `order.qrPayload`: el identificador del pedido en el
/// servidor (`pedidos.id`) o, en las órdenes locales, el número visible. El
/// servidor (`buscar_pedido_personal`) acepta ambos, así que el QR siempre se
/// puede buscar sin exponer tokens de sesión ni claves.
///
/// El número de orden sigue visible en pantalla para poder buscarlo a mano.
class OrderQr extends StatelessWidget {
  const OrderQr({
    super.key,
    required this.order,
    this.size = 160,
    this.padding = 8,
  });

  final Order order;
  final double size;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.all(padding),
      child: QrImageView(
        data: order.qrPayload,
        version: QrVersions.auto,
        size: size,
        gapless: true,
        backgroundColor: Colors.white,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: AppColors.ink,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: AppColors.ink,
        ),
        errorStateBuilder: (BuildContext context, Object? error) {
          return SizedBox(
            width: size,
            height: size,
            child: Center(
              child: Text(
                'No se pudo dibujar el QR de la orden.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          );
        },
      ),
    );
  }
}
