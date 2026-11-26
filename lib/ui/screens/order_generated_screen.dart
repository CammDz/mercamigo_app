import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/order.dart';
import '../../services/order_share_service.dart';
import '../../state/store_location_controller.dart';
import '../widgets/order_expiry_countdown.dart';
import '../widgets/order_qr.dart';
import 'order_share_capture_screen.dart';

/// Argumentos de la pantalla de orden generada.
class OrderGeneratedArgs {
  const OrderGeneratedArgs({required this.order});

  final Order order;
}

/// Código QR de la orden con la distribución aprobada en Figma.
///
/// El QR conserva el identificador real de Supabase; el número visible permite
/// que el cliente pueda dictar la orden si no puede mostrar el código.
class OrderGeneratedScreen extends StatefulWidget {
  const OrderGeneratedScreen({super.key, required this.order});

  static const String routeName = '/order';

  final Order order;

  @override
  State<OrderGeneratedScreen> createState() => _OrderGeneratedScreenState();
}

class _OrderGeneratedScreenState extends State<OrderGeneratedScreen> {
  bool _sharing = false;
  bool _expired = false;

  Future<void> _share(BuildContext context) async {
    if (_sharing) return;
    if (_expired || widget.order.isExpired) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La orden caducó: el código ya no es válido.'),
        ),
      );
      return;
    }

    setState(() => _sharing = true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final StoreLocationController store = context
        .read<StoreLocationController>();
    final String storeName = store.location.name?.isNotEmpty == true
        ? store.location.name!
        : 'Mercamigo';

    try {
      final Uint8List? bytes = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute<Uint8List>(
          fullscreenDialog: true,
          builder: (BuildContext context) => OrderShareCaptureScreen(
            order: widget.order,
            storeName: storeName,
          ),
        ),
      );
      if (bytes == null || bytes.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No se pudo preparar la imagen.')),
        );
        return;
      }

      final ShareResultStatus status = await OrderShareService.shareOrderImage(
        bytes: bytes,
        orderNumber: widget.order.orderNumber,
        storeName: storeName,
      );
      if (status == ShareResultStatus.unavailable) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No hay una app para compartir.')),
        );
      }
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo compartir la orden: $error')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double scale = math.min(
              1,
              math.min(constraints.maxWidth / 360, constraints.maxHeight / 800),
            );
            final double designWidth = 360 * scale;
            final double designHeight = 800 * scale;

            return SingleChildScrollView(
              child: SizedBox(
                width: constraints.maxWidth,
                height: math.max(constraints.maxHeight, designHeight),
                child: Center(
                  child: SizedBox(
                    width: designWidth,
                    height: designHeight,
                    child: FittedBox(
                      fit: BoxFit.fill,
                      child: SizedBox(
                        width: 360,
                        height: 800,
                        child: Stack(
                          children: <Widget>[
                            Positioned(
                              top: 43,
                              left: 0,
                              width: 360,
                              child: Text(
                                'Orden generada',
                                textAlign: TextAlign.center,
                                style: AppText.body(
                                  32,
                                  weight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Positioned(
                              left: 32,
                              top: 84,
                              width: 295,
                              height: 533,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: AppColors.grayBorder,
                                    width: 1,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 50,
                              top: 107,
                              width: 260,
                              child: Text(
                                'Tu numero de orden',
                                textAlign: TextAlign.center,
                                style: AppText.body(
                                  20,
                                  weight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Positioned(
                              left: 44,
                              top: 156,
                              width: 272,
                              height: 44,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '#${widget.order.orderNumber.replaceFirst(RegExp(r'^#'), '')}',
                                  style: AppText.body(
                                    64,
                                    weight: FontWeight.w800,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 92,
                              top: 206,
                              width: 176,
                              height: 176,
                              child: Center(
                                child: OrderQr(
                                  order: widget.order,
                                  size: 132,
                                  padding: 0,
                                ),
                              ),
                            ),
                            Positioned(
                              left: 50,
                              top: 402,
                              width: 260,
                              child: Text(
                                'Muestra este QR al cajero\no indica tu número de orden.',
                                textAlign: TextAlign.center,
                                style: AppText.body(
                                  16,
                                  weight: FontWeight.w500,
                                  height: 1.3,
                                ),
                              ),
                            ),
                            Positioned(
                              left: 52,
                              top: 520,
                              width: 256,
                              height: 58,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: OrderExpiryCountdown(
                                  order: widget.order,
                                  labelPrefix: 'La orden expira en',
                                  labelSuffix: ' min',
                                  fontSize: 24,
                                  iconSize: 32,
                                  multiline: true,
                                  onExpired: () {
                                    if (mounted) {
                                      setState(() => _expired = true);
                                    }
                                  },
                                ),
                              ),
                            ),
                            Positioned(
                              left: 47,
                              top: 638,
                              width: 265,
                              height: 57,
                              child: OutlinedButton(
                                onPressed: _sharing
                                    ? null
                                    : () => _share(context),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.ink,
                                  side: const BorderSide(
                                    color: AppColors.grayBorderDark,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  padding: EdgeInsets.zero,
                                  textStyle: AppText.body(
                                    20,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                                child: _sharing
                                    ? const SizedBox.square(
                                        dimension: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: <Widget>[
                                          const Icon(
                                            Icons.share_outlined,
                                            size: 22,
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            'Compartir Orden',
                                            style: AppText.body(
                                              20,
                                              weight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                            Positioned(
                              left: 125,
                              top: 740,
                              width: 110,
                              height: 36,
                              child: TextButton(
                                onPressed: () => Navigator.of(context).popUntil(
                                  (Route<dynamic> route) => route.isFirst,
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.ink,
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: <Widget>[
                                    const Icon(Icons.close, size: 24),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Cerrar',
                                      style: AppText.body(
                                        20,
                                        weight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
