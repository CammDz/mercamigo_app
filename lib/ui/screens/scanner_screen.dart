import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/product.dart';
import '../../repositories/catalog_repository.dart';
import '../../repositories/scan_history_repository.dart';
import '../../services/auth_service.dart';
import '../../services/camera_permission_service.dart';
import '../../services/scanner_service.dart';
import '../widgets/barcode_scanner_view.dart';
import '../widgets/primary_button.dart';
import 'manual_code_dialog.dart';
import 'product_detail_screen.dart';
import 'scan_history_screen.dart';

/// Estado del escáner, para poder explicar siempre qué pasa.
enum CameraStatus {
  /// La cámara está arrancando.
  starting,

  /// La cámara está lista y escaneando.
  ready,

  /// Falta el permiso de cámara: la app va a pedirlo.
  permissionPending,

  /// El permiso se denegó (se puede volver a pedir).
  permissionDenied,

  /// El permiso está bloqueado: hay que ir a Ajustes.
  permissionBlocked,

  /// Este dispositivo no tiene cámara utilizable.
  unavailable,

  /// Error al iniciar la cámara.
  error,
}

/// Escáner de códigos con la cámara real.
///
/// Lee códigos de barras, busca el valor leído en los códigos
/// registrados del catálogo y pausa el escaneo al detectar un código para
/// evitar duplicados.
///
/// La pantalla nunca queda en negro sin explicación: si la cámara no arranca
/// se dice por qué y siempre queda disponible el ingreso manual del código.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  static const String routeName = '/scanner';

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  late final ScannerService _scanner;

  /// `true` mientras se procesa un código: evita detecciones duplicadas.
  bool _handling = false;

  /// Estado actual de la cámara.
  CameraStatus _status = CameraStatus.starting;

  /// Detalle del error (para el registro).
  String? _errorDetails;

  /// `true` si el dispositivo no tiene flash utilizable.
  bool _torchUnavailable = false;

  /// Señal visual del último enfoque pedido (no es el enfoque en sí).
  bool _focusVisible = false;
  int _focusToken = 0;

  /// Servicio para consultar el permiso (no lo pide: el plugin lo hace).
  static const CameraPermissionService _permissions = CameraPermissionService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scanner = ScannerService(
      catalogRepository: context.read<CatalogRepository>(),
    );
    // El controlador avisa cuando la cámara arranca (o se cae).
    _scanner.controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPermission());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanner.controller.removeListener(_onControllerChanged);
    // Al salir se apaga la linterna y se libera la cámara.
    _scanner.dispose();
    super.dispose();
  }

  /// Reacciona al estado del controlador: la cámara puede arrancar o caerse.
  void _onControllerChanged() {
    if (!mounted) return;
    final MobileScannerState state = _scanner.controller.value;
    if (state.isRunning) {
      if (_status != CameraStatus.ready) {
        setState(() => _status = CameraStatus.ready);
      }
      return;
    }
    final MobileScannerException? error = state.error;
    if (error != null && _status == CameraStatus.ready) {
      _onScannerError(error);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final MobileScannerController controller = _scanner.controller;
    if (!controller.value.isInitialized) return;
    if (state == AppLifecycleState.resumed) {
      // `start()` no hace nada si la cámara ya está arrancada.
      _scanner.start();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _scanner.pause();
    }
  }

  /// Consulta el permiso antes de arrancar y lo **pide siempre** que falte.
  ///
  /// Android solo muestra el diálogo mientras el usuario no haya marcado
  /// "no volver a preguntar"; si ya está bloqueado, se ofrece Ajustes.
  Future<void> _checkPermission() async {
    CameraPermissionStatus permission = await _permissions.status();
    if (!mounted) return;

    if (permission == CameraPermissionStatus.denied ||
        permission == CameraPermissionStatus.pending) {
      permission = await _permissions.request();
      if (!mounted) return;
    }

    switch (permission) {
      case CameraPermissionStatus.granted:
        setState(() => _status = CameraStatus.starting);
        await _scanner.start();
      case CameraPermissionStatus.denied:
        setState(() => _status = CameraStatus.permissionDenied);
      case CameraPermissionStatus.blocked:
        setState(() => _status = CameraStatus.permissionBlocked);
      case CameraPermissionStatus.pending:
      case CameraPermissionStatus.unknown:
        // El plugin pide el permiso al arrancar la cámara.
        setState(() => _status = CameraStatus.starting);
        await _scanner.start();
    }
  }

  /// Traduce el error de la cámara a un estado explicable.
  Future<void> _onScannerError(MobileScannerException error) async {
    if (!mounted) return;
    setState(
      () => _errorDetails =
          '${error.errorCode} ${error.errorDetails?.message ?? ''}',
    );

    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        // Se consulta el permiso para saber si se puede volver a pedir o
        // si está bloqueado.
        final CameraPermissionStatus permission = await _permissions.status();
        if (!mounted) return;
        setState(() {
          _status = switch (permission) {
            CameraPermissionStatus.blocked => CameraStatus.permissionBlocked,
            CameraPermissionStatus.granted => CameraStatus.error,
            _ => CameraStatus.permissionDenied,
          };
        });
      case MobileScannerErrorCode.unsupported:
        setState(() => _status = CameraStatus.unavailable);
      case MobileScannerErrorCode.controllerDisposed:
      case MobileScannerErrorCode.controllerUninitialized:
        // Carrera del ciclo de vida: no es un fallo de la cámara.
        break;
      default:
        setState(() => _status = CameraStatus.error);
    }
  }

  /// Apaga la linterna y reinicia la cámara.
  Future<void> _restartCamera() async {
    await _scanner.stopTorch();
    await _scanner.restart();
  }

  Future<void> _onDetectRaw(String rawCode) async {
    if (_handling) return;
    final String raw = rawCode.trim();
    if (raw.isEmpty) return;

    // Se pausa el procesamiento antes de continuar para no detectar el
    // mismo código varias veces.
    _handling = true;
    await _scanner.pause();

    final ScanResult result = _scanner.resolve(raw);
    if (!mounted) return;

    if (result.isFound) {
      final Product product = result.product!;
      await _recordScan(product, raw);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: ProductDetailScreen.routeName),
          builder: (BuildContext context) =>
              ProductDetailScreen(product: product, origin: 'Escáner'),
        ),
      );
    } else {
      await _showNotFound(raw);
    }

    if (!mounted) return;
    _handling = false;
    await _scanner.resume();
  }

  /// Guarda el escaneo en el historial del usuario.
  Future<void> _recordScan(Product product, String code) async {
    try {
      final ScanHistoryRepository repository = context
          .read<ScanHistoryRepository>();
      final String? email = context.read<AuthService>().email;
      await repository.add(
        email ?? 'anon',
        ScanHistoryEntry(
          productId: product.id,
          productName: product.name,
          code: code,
          imageUrl: product.imageUrl,
          scannedAt: DateTime.now(),
        ),
      );
    } catch (_) {
      // El historial es un extra: si falla, el escaneo sigue funcionando.
    }
  }

  Future<void> _showNotFound(String rawCode) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Producto no encontrado',
          style: AppText.body(19, weight: FontWeight.w700),
        ),
        content: Text(
          'El código leído no está registrado en el catálogo.\n\n'
          'Código leído: $rawCode',
          style: AppText.body(15, color: AppColors.muted),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Entendido', style: AppText.body(15)),
          ),
        ],
      ),
    );
  }

  Future<void> _openManualEntry() async {
    final String? code = await showManualCodeDialog(context);
    if (code == null || !mounted) return;
    final ScanResult result = _scanner.resolve(code);
    if (!mounted) return;
    if (result.isFound) {
      final Product product = result.product!;
      await _recordScan(product, code);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: ProductDetailScreen.routeName),
          builder: (BuildContext context) =>
              ProductDetailScreen(product: product, origin: 'Escáner'),
        ),
      );
    } else {
      await _showNotFound(code);
    }
  }

  /// Enciende o apaga la linterna y refleja el estado real.
  Future<void> _toggleTorch() async {
    if (_status != CameraStatus.ready || _torchUnavailable) return;
    try {
      await _scanner.toggleTorch();
    } on MobileScannerException {
      // El dispositivo no tiene flash utilizable.
      if (!mounted) return;
      setState(() => _torchUnavailable = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _torchUnavailable = true);
    }
  }

  /// Pide a la cámara que enfoque el centro del marco.
  ///
  /// Es una acción real de `MobileScannerController.setFocusPoint`; el
  /// autoenfoque sigue activo y el toque sobre la vista previa también
  /// enfoca (ver `BarcodeScannerView.tapToFocus`). Nunca toca la linterna.
  Future<void> _focusCenter() async {
    if (_status != CameraStatus.ready) return;
    try {
      await _scanner.focusAt(const Offset(0.5, 0.5));
      if (!mounted) return;
      final int token = ++_focusToken;
      setState(() => _focusVisible = true);
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted || token != _focusToken) return;
      setState(() => _focusVisible = false);
    } on MobileScannerException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo fijar el enfoque: '
            '${error.errorDetails?.message ?? 'cámara no disponible'}.',
          ),
        ),
      );
    } catch (_) {
      // El equipo puede no admitir un punto de enfoque manual. El
      // autoenfoque continúa; no se simula ninguna acción.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este equipo no permite fijar el enfoque; '
            'la cámara enfoca automáticamente.',
          ),
        ),
      );
    }
  }

  /// Abre los ajustes de la app para cambiar el permiso.
  Future<void> _openSettings() async {
    await _permissions.openSettings();
  }

  @override
  Widget build(BuildContext context) {
    final bool cameraReady = _status == CameraStatus.ready;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // La vista de la cámara se construye siempre: es ella la que pide
          // el permiso y la que avisa cuando la cámara está lista. Mientras
          // tanto, el panel de estado explica lo que pasa (nunca un negro
          // sin explicación).
          BarcodeScannerView(
            controller: _scanner.controller,
            onDetected: (String raw) => _onDetectRaw(raw),
            onError: _onScannerError,
            overlay: const ColoredBox(color: Color(0x7330343A)),
          ),
          SafeArea(
            child: Column(
              children: <Widget>[
                _TopBar(
                  onClose: () => Navigator.of(context).maybePop(),
                  onManualEntry: _openManualEntry,
                ),
                const SizedBox(height: 4),
                Text(
                  'Escanea el código de barras\ndel producto',
                  textAlign: TextAlign.center,
                  style: AppText.display(23, color: Colors.white, height: 1.22),
                ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 29),
                      child: AspectRatio(
                        aspectRatio: 302 / 142,
                        child: Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                              ),
                            ),
                            Center(
                              child: ScannerFocusReticle(
                                visible: _focusVisible,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (!cameraReady)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _CameraStatusPanel(
                      status: _status,
                      details: _errorDetails,
                      onOpenSettings: _openSettings,
                      onRetry: () {
                        setState(() => _status = CameraStatus.starting);
                        _restartCamera();
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                _BottomBar(
                  scanner: _scanner,
                  cameraReady: cameraReady,
                  torchUnavailable: _torchUnavailable,
                  onFocus: _focusCenter,
                  onToggleTorch: _toggleTorch,
                  onHistory: () =>
                      Navigator.of(context)
                          .pushNamed(ScanHistoryScreen.routeName),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Panel que explica el estado de la cámara.
class _CameraStatusPanel extends StatelessWidget {
  const _CameraStatusPanel({
    required this.status,
    required this.details,
    required this.onOpenSettings,
    required this.onRetry,
  });

  final CameraStatus status;
  final String? details;
  final VoidCallback onOpenSettings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final String message = switch (status) {
      CameraStatus.starting => 'Encendiendo la cámara…',
      CameraStatus.permissionPending =>
        'Se necesita el permiso de cámara para escanear códigos.',
      CameraStatus.permissionDenied =>
        'Permiso de cámara denegado. Actívalo para poder escanear; '
            'mientras tanto puedes escribir el código a mano.',
      CameraStatus.permissionBlocked =>
        'El permiso de cámara está bloqueado. Actívalo en los ajustes del '
            'sistema para volver a escanear.',
      CameraStatus.unavailable =>
        'Este dispositivo no tiene una cámara disponible para escanear. '
            'Puedes escribir el código a mano.',
      CameraStatus.error =>
        'No se pudo iniciar la cámara. Puedes escribir el código a mano.',
      CameraStatus.ready => '',
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                status == CameraStatus.starting
                    ? Icons.hourglass_empty
                    : Icons.no_photography_outlined,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: AppText.body(14, color: Colors.white, height: 1.35),
                ),
              ),
            ],
          ),
          if (status == CameraStatus.permissionBlocked ||
              status == CameraStatus.permissionDenied) ...<Widget>[
            const SizedBox(height: 10),
            PrimaryButton.outlined(
              label: 'Abrir ajustes',
              icon: Icons.settings_outlined,
              height: 44,
              onPressed: onOpenSettings,
            ),
          ],
          if (status == CameraStatus.error ||
              status == CameraStatus.unavailable) ...<Widget>[
            const SizedBox(height: 10),
            PrimaryButton.outlined(
              label: 'Reintentar',
              icon: Icons.refresh,
              height: 44,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}

/// Barra superior del escáner.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.onClose, required this.onManualEntry});

  final VoidCallback onClose;
  final VoidCallback onManualEntry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 6, 0),
      child: SizedBox(
        height: 52,
        child: Row(
          children: <Widget>[
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              tooltip: 'Cerrar',
            ),
            Expanded(
              child: Text(
                'Escanear producto',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.display(25, color: Colors.white),
              ),
            ),
            IconButton(
              onPressed: onManualEntry,
              icon: const Icon(
                Icons.keyboard_outlined,
                color: Colors.white,
                size: 28,
              ),
              tooltip: 'Ingresar código manualmente',
            ),
          ],
        ),
      ),
    );
  }
}

/// Barra inferior: historial, botón de enfoque y linterna.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.scanner,
    required this.cameraReady,
    required this.torchUnavailable,
    required this.onFocus,
    required this.onToggleTorch,
    required this.onHistory,
  });

  final ScannerService scanner;
  final bool cameraReady;
  final bool torchUnavailable;
  final VoidCallback onFocus;
  final VoidCallback onToggleTorch;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          _BottomAction(
            label: 'Historial',
            icon: Icons.history,
            onTap: onHistory,
          ),
          Tooltip(
            message: 'Enfocar el código',
            child: GestureDetector(
              onTap: cameraReady ? onFocus : null,
              child: Opacity(
                opacity: cameraReady ? 1 : 0.4,
                child: SizedBox(
                  height: 78,
                  width: 78,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                    ),
                    child: const Icon(
                      Icons.center_focus_strong,
                      color: Colors.white,
                      size: 39,
                    ),
                  ),
                ),
              ),
            ),
          ),
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: scanner.controller,
            builder: (BuildContext context, MobileScannerState state, _) {
              final bool on = state.torchState == TorchState.on;
              // La etiqueta es la de Figma; el icono refleja el estado real.
              return _BottomAction(
                label: torchUnavailable ? 'Sin flash' : 'Linterna',
                icon: torchUnavailable
                    ? Icons.flashlight_off
                    : (on ? Icons.flashlight_on : Icons.flashlight_off),
                onTap: cameraReady && !torchUnavailable ? onToggleTorch : null,
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Botón de la barra inferior.
class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: Colors.white, size: 34),
            const SizedBox(height: 6),
            Text(label, style: AppText.body(15, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
