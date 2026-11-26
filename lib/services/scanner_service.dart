import 'dart:ui' show Offset;

import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/models/product.dart';
import '../repositories/catalog_repository.dart';

/// Resultado de interpretar un valor leído por la cámara.
enum ScanResolution {
  /// El valor corresponde a un producto del catálogo.
  found,

  /// El valor es válido pero no está registrado en el catálogo.
  notFound,

  /// El valor leído está vacío.
  invalid,
}

/// Resultado de resolver un código escaneado.
class ScanResult {
  const ScanResult(this.resolution, {this.product, this.rawCode});

  final ScanResolution resolution;
  final Product? product;
  final String? rawCode;

  bool get isFound => resolution == ScanResolution.found;
}

/// Envoltura del lector de códigos con la cámara real.
///
/// El valor leído se trata siempre como un token opaco: se busca en el índice
/// de códigos registrados del catálogo y nunca se abre ni se ejecuta como URL.
class ScannerService {
  ScannerService({
    required this._catalogRepository,
    MobileScannerController? controller,
  }) : controller =
           controller ??
           MobileScannerController(
             // El arranque lo hace la pantalla (un solo sitio), no el widget:
             // con `autoStart` en true los dos mecanismos compiten y la
             // cámara falla con "Called start() while already started".
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

  final CatalogRepository _catalogRepository;

  /// Controlador de la cámara. Se expone para encender/apagar la linterna y
  /// para pausar el escaneo mientras se muestra un producto.
  final MobileScannerController controller;

  /// Resuelve un valor leído por la cámara contra el catálogo.
  ScanResult resolve(String? rawCode) {
    final String code = (rawCode ?? '').trim();
    if (code.isEmpty) {
      return const ScanResult(ScanResolution.invalid);
    }
    final Product? product = _catalogRepository.findByCode(code);
    if (product == null) {
      return ScanResult(ScanResolution.notFound, rawCode: code);
    }
    return ScanResult(ScanResolution.found, product: product, rawCode: code);
  }

  /// Arranca la cámara (una sola vez: el widget no la arranca solo).
  ///
  /// Si la cámara ya está en marcha no hace nada.
  Future<void> start() async {
    if (controller.value.isRunning) return;
    try {
      await controller.start();
    } on MobileScannerException {
      // La pantalla ya muestra el estado del error.
    } on Exception {
      // Igual: la pantalla lo explica.
    }
  }

  /// Pausa el escaneo (se usa al detectar un código para evitar duplicados).
  Future<void> pause() async {
    if (!controller.value.isInitialized) return;
    try {
      await controller.stop();
    } on Exception {
      // Si la cámara ya estaba detenida no hay nada que hacer.
    }
  }

  /// Reanuda el escaneo.
  Future<void> resume() async {
    try {
      await controller.start();
    } on Exception {
      // La cámara puede no estar disponible; la pantalla lo informa.
    }
  }

  /// Reinicia la cámara (tras un error o al volver de Ajustes).
  Future<void> restart() async {
    try {
      await controller.stop();
    } on Exception {
      // Ignorado: puede que ya estuviera parada.
    }
    try {
      await controller.start();
    } on Exception {
      // La pantalla ya muestra el estado del error.
    }
  }

  /// Enciende o apaga la linterna.
  ///
  /// El plugin lanza una excepción si la cámara no está arrancada o si el
  /// dispositivo no tiene flash: eso se traduce en "sin flash" en la
  /// pantalla, no en un fallo silencioso.
  Future<void> toggleTorch() async {
    await controller.toggleTorch();
  }

  /// Pide a la cámara que enfoque un punto concreto de la vista previa.
  ///
  /// [position] se expresa en coordenadas normalizadas (0,0) a (1,1), que es
  /// lo que acepta `MobileScannerController.setFocusPoint`. Es una acción real
  /// de la cámara: no hay animación ni temporizador que simule el enfoque.
  Future<void> focusAt(Offset position) async {
    if (!controller.value.isRunning) return;
    await controller.setFocusPoint(position);
  }

  /// Apaga la linterna (al salir del escáner).
  Future<void> stopTorch() async {
    try {
      if (controller.value.torchState == TorchState.on) {
        await controller.toggleTorch();
      }
    } on Exception {
      // Si la cámara ya está cerrada, la linterna está apagada.
    }
  }

  Future<void> dispose() async {
    await stopTorch();
    await controller.dispose();
  }
}
