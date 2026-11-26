import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_typography.dart';

/// Visor de códigos con la cámara.
///
/// Se usa tanto en el escáner del comprador como en el registro de códigos
/// del administrador y en la pantalla de diagnóstico.
///
/// El error de la cámara se registra **completo** (código, mensaje y traza)
/// y se avisa **una sola vez por error distinto**: si se notificara en cada
/// reconstrucción, el propio aviso provocaría otra reconstrucción y la
/// cámara entraría en un bucle de reintentos.
class BarcodeScannerView extends StatefulWidget {
  const BarcodeScannerView({
    super.key,
    required this.controller,
    required this.onDetected,
    this.formats = defaultBarcodeFormats,
    this.overlay,
    this.onError,
    this.onReady,
    this.tapToFocus = true,
  });

  /// Controlador de la cámara (lo usa el exterior para la linterna).
  final MobileScannerController controller;

  /// Se llama con el valor leído (texto opaco).
  final ValueChanged<String> onDetected;

  /// Formatos de código aceptados.
  final List<BarcodeFormat> formats;

  /// Contenido superpuesto (marco de escaneo, textos...).
  final Widget? overlay;

  /// Se llama cuando la cámara falla (una vez por error distinto).
  final ValueChanged<MobileScannerException>? onError;

  /// Se llama cuando la cámara está lista para escanear.
  final VoidCallback? onReady;

  /// Permite tocar la vista previa para enfocar ese punto.
  ///
  /// Lo implementa el propio plugin (`MobileScanner.tapToFocus`) con una
  /// acción real de la cámara; no es una animación.
  final bool tapToFocus;

  /// Formatos que usa el escáner de **productos**: solo códigos de barras.
  ///
  /// Los productos se identifican con códigos de barras (Code 128, EAN…). Los
  /// pedidos usan un escáner distinto y solo aceptan QR ([defaultQrFormats]).
  static const List<BarcodeFormat> defaultBarcodeFormats = <BarcodeFormat>[
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upcA,
    BarcodeFormat.upcE,
    BarcodeFormat.code128,
    BarcodeFormat.code39,
    BarcodeFormat.itf14,
  ];

  /// Formatos del escáner de **pedidos**: solo QR.
  static const List<BarcodeFormat> defaultQrFormats = <BarcodeFormat>[
    BarcodeFormat.qrCode,
  ];

  @override
  State<BarcodeScannerView> createState() => _BarcodeScannerViewState();
}

class _BarcodeScannerViewState extends State<BarcodeScannerView> {
  String? _error;
  String? _reportedError;

  /// Traduce el error de la cámara a un mensaje entendible.
  ///
  /// El mensaje real del plugin se registra aparte (ver [_reportError]): aquí
  /// solo se muestra una explicación para la persona que usa la app.
  String _messageFor(MobileScannerException error) {
    return switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'Permiso de cámara denegado. Actívalo en los ajustes del sistema.',
      MobileScannerErrorCode.unsupported =>
        'Este dispositivo no soporta el escáner.',
      _ => 'No se pudo iniciar la cámara. Ingresa el código a mano.',
    };
  }

  /// Registra el error completo y avisa **una sola vez** por error distinto.
  void _reportError(MobileScannerException error) {
    final MobileScannerErrorDetails? details = error.errorDetails;
    final String signature =
        '${error.errorCode}|${details?.code}|${details?.message}';
    if (_reportedError == signature) return;
    _reportedError = signature;

    // Registro completo: código del plugin, código de la plataforma,
    // mensaje y detalles.
    debugPrint(
      '[Mercamigo/scanner] MobileScanner error\n'
      '  code=${error.errorCode}\n'
      '  platformCode=${details?.code}\n'
      '  message=${details?.message}\n'
      '  details=${details?.details}',
    );

    widget.onError?.call(error);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        MobileScanner(
          controller: widget.controller,
          tapToFocus: widget.tapToFocus,
          onDetect: (BarcodeCapture capture) {
            for (final Barcode barcode in capture.barcodes) {
              final String? raw = barcode.rawValue;
              if (raw == null || raw.trim().isEmpty) continue;
              widget.onDetected(raw.trim());
              return;
            }
          },
          errorBuilder: (BuildContext context, MobileScannerException error) {
            // Se avisa una sola vez por error distinto: si se notificara en
            // cada reconstrucción, el aviso provocaría otra reconstrucción
            // y la cámara entraría en un bucle.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _reportError(error);
              if (_error == null) {
                setState(() => _error = _messageFor(error));
              }
            });
            return const ColoredBox(color: Colors.black);
          },
          placeholderBuilder: (BuildContext context) =>
              const ColoredBox(color: Colors.black),
        ),
        // El velo es solo decorativo: no debe bloquear el toque que enfoca.
        if (widget.overlay != null) IgnorePointer(child: widget.overlay!),
        if (_error != null)
          ColoredBox(
            color: Colors.black.withValues(alpha: 0.75),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: AppText.body(14.5, color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Señal visual de que se pidió enfoque a la cámara.
///
/// Solo se muestra después de llamar a `setFocusPoint`: no simula el enfoque
/// ni lo sustituye, únicamente confirma que la acción se envió.
class ScannerFocusReticle extends StatelessWidget {
  const ScannerFocusReticle({super.key, required this.visible, this.size = 76});

  final bool visible;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
