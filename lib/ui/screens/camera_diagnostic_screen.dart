import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_typography.dart';
import '../widgets/app_top_bar.dart';

/// Pantalla mínima de diagnóstico de la cámara.
///
/// Un único escáner y un único controlador, sin carrito, sin GPS y sin
/// navegación adicional: sirve para saber si falla el **plugin o el
/// dispositivo** o la integración de la pantalla normal.
///
/// Muestra en pantalla el error real (código del plugin, código de la
/// plataforma y mensaje) y el estado de la linterna.
class CameraDiagnosticScreen extends StatefulWidget {
  const CameraDiagnosticScreen({super.key});

  static const String routeName = '/diagnostico/camara';

  @override
  State<CameraDiagnosticScreen> createState() => _CameraDiagnosticScreenState();
}

class _CameraDiagnosticScreenState extends State<CameraDiagnosticScreen> {
  late final MobileScannerController _controller;

  String _estado = 'Iniciando…';
  String? _error;
  String _codigo = '-';
  String _mensaje = '-';
  String _detalle = '-';
  bool _linternaEncendida = false;

  @override
  void initState() {
    super.initState();
    // `autoStart: false`: el arranque lo hacemos nosotros, una sola vez, para
    // no competir con el arranque automático del widget.
    _controller = MobileScannerController(
      autoStart: false,
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const <BarcodeFormat>[
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.itf14,
      ],
    );
    _controller.addListener(_alCambiarEstado);
    WidgetsBinding.instance.addPostFrameCallback((_) => _arrancar());
  }

  @override
  void dispose() {
    _controller.removeListener(_alCambiarEstado);
    _controller.dispose();
    super.dispose();
  }

  void _alCambiarEstado() {
    if (!mounted) return;
    final MobileScannerState state = _controller.value;
    setState(() {
      _estado = state.isRunning
          ? 'Cámara EN MARCHA'
          : (state.isInitialized
                ? 'Cámara detenida'
                : 'Cámara no inicializada');
      _linternaEncendida = state.torchState == TorchState.on;
    });
  }

  Future<void> _arrancar() async {
    try {
      await _controller.start();
      if (!mounted) return;
      setState(() => _estado = 'Cámara EN MARCHA');
    } on MobileScannerException catch (error, stack) {
      _registrar(error, stack);
    } catch (error, stack) {
      _registrar(error, stack);
    }
  }

  void _registrar(Object error, StackTrace stack) {
    if (!mounted) return;
    final MobileScannerException? scannerError = error is MobileScannerException
        ? error
        : null;
    final MobileScannerErrorDetails? details = scannerError?.errorDetails;
    setState(() {
      _estado = 'ERROR al iniciar';
      _error = error.toString();
      _codigo = scannerError?.errorCode.name ?? 'excepción';
      _mensaje = details?.message ?? '-';
      _detalle = details?.code ?? '-';
    });
    debugPrint('[Mercamigo/diagnostico] $error\n$stack');
  }

  Future<void> _alternarLinterna() async {
    try {
      await _controller.toggleTorch();
    } on MobileScannerException catch (error, stack) {
      _registrar(error, stack);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppTopBar(
        title: 'Diagnóstico cámara',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            SizedBox(
              height: 260,
              child: MobileScanner(
                controller: _controller,
                tapToFocus: true,
                onDetect: (BarcodeCapture capture) {
                  debugPrint(
                    '[Mercamigo/diagnostico] código leído: '
                    '${capture.barcodes.map((Barcode b) => b.rawValue).toList()}',
                  );
                },
                errorBuilder:
                    (BuildContext context, MobileScannerException error) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        _registrar(error, StackTrace.current);
                      });
                      return const ColoredBox(color: Colors.black);
                    },
              ),
            ),
            const SizedBox(height: 14),
            _Fila(etiqueta: 'Estado', valor: _estado),
            _Fila(etiqueta: 'Código', valor: _codigo),
            _Fila(etiqueta: 'Mensaje', valor: _mensaje),
            _Fila(etiqueta: 'Detalle', valor: _detalle),
            _Fila(
              etiqueta: 'Linterna',
              valor: _linternaEncendida ? 'encendida' : 'apagada',
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: AppText.body(12.5, color: Colors.white),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: ElevatedButton(
                    onPressed: _arrancar,
                    child: const Text('Reintentar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _alternarLinterna,
                    child: const Text('Linterna'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila etiqueta/valor del diagnóstico.
class _Fila extends StatelessWidget {
  const _Fila({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              etiqueta,
              style: AppText.body(
                13,
                weight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          Expanded(
            child: Text(valor, style: AppText.body(13, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
