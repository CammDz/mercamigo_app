import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/order.dart';
import '../widgets/order_share_card.dart';

/// Captura la tarjeta de la orden como imagen PNG.
///
/// Se abre como una ruta aparte para poder renderizar la tarjeta **completa**
/// (no recortada a lo que se ve en pantalla) y capturarla con el logo y el
/// código QR ya pintados. Al terminar hace `pop` con los bytes de la
/// imagen (o `null` si algo falla).
class OrderShareCaptureScreen extends StatefulWidget {
  const OrderShareCaptureScreen({
    super.key,
    required this.order,
    required this.storeName,
  });

  final Order order;
  final String storeName;

  @override
  State<OrderShareCaptureScreen> createState() =>
      _OrderShareCaptureScreenState();
}

class _OrderShareCaptureScreenState extends State<OrderShareCaptureScreen> {
  final GlobalKey _boundaryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
  }

  Future<void> _capture() async {
    Uint8List? bytes;
    try {
      // El logo tiene que estar pintado antes de capturar.
      await precacheImage(const AssetImage('assets/figma/logo.png'), context);
      // Un frame más para que la tarjeta esté maquetada.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      final RenderRepaintBoundary? boundary =
          _boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        _finish(null);
        return;
      }

      // 2x mantiene el código QR legible sin una imagen enorme.
      final ui.Image image = await boundary.toImage(pixelRatio: 2);
      final ByteData? data = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      image.dispose();

      if (data == null || data.lengthInBytes == 0) {
        _finish(null);
        return;
      }
      bytes = data.buffer.asUint8List();
    } catch (_) {
      bytes = null;
    }
    _finish(bytes);
  }

  void _finish(Uint8List? bytes) {
    if (!mounted) return;
    Navigator.of(context).pop<Uint8List>(bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: RepaintBoundary(
            key: _boundaryKey,
            child: OrderShareCard(
              order: widget.order,
              storeName: widget.storeName,
            ),
          ),
        ),
      ),
    );
  }
}

/// Aviso de que la imagen se está preparando.
class OrderSharePreparing extends StatelessWidget {
  const OrderSharePreparing({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(strokeWidth: 3),
      ),
    );
  }
}

/// Texto de ayuda sobre la privacidad de la imagen.
class OrderSharePrivacyNote extends StatelessWidget {
  const OrderSharePrivacyNote({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text(
      'La imagen contiene el número y el código QR de la orden. '
      'Compártela solo con la persona autorizada.',
      style: TextStyle(fontSize: 12, color: AppColors.muted),
    );
  }
}
