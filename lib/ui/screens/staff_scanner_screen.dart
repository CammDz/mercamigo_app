import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/staff_order.dart';
import '../../repositories/staff_repository.dart';
import '../widgets/barcode_scanner_view.dart';
import 'staff_history_screen.dart';

/// Escáner de pedidos para la caja.
///
/// Solo acepta **códigos QR**: los pedidos usan QR (identificador del pedido
/// en el servidor) y los productos usan códigos de barras en su propio
/// escáner. También permite escribir el número visible a mano.
///
/// La búsqueda la hace el servidor y exige el rol de caja: el código **no**
/// autoriza nada por sí solo.
class StaffScannerScreen extends StatefulWidget {
  const StaffScannerScreen({super.key});

  @override
  State<StaffScannerScreen> createState() => _StaffScannerScreenState();
}

class _StaffScannerScreenState extends State<StaffScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: BarcodeScannerView.defaultQrFormats,
  );

  bool _searching = false;
  bool _torchOn = false;
  String? _message;

  /// Señal visual del último enfoque pedido (no es el enfoque en sí).
  bool _focusVisible = false;
  int _focusToken = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetected(String raw) async {
    if (_searching) return;
    await _search(raw);
  }

  Future<void> _search(String code) async {
    final String value = code.trim();
    if (value.isEmpty || _searching) return;
    setState(() {
      _searching = true;
      _message = null;
    });

    try {
      final StaffOrderSearchResult result = await context
          .read<StaffRepository>()
          .findByCode(value);
      if (!mounted) return;
      final StaffOrderDetail? order = result.order;
      if (result.found && order != null) {
        Navigator.of(context).pop<StaffOrderDetail>(order);
        return;
      }
      setState(() {
        _message =
            result.message ?? 'No se encontró ningún pedido con ese código QR.';
      });
      await Future<void>.delayed(const Duration(milliseconds: 1400));
    } on StaffException catch (error) {
      if (!mounted) return;
      setState(() => _message = error.message);
      await Future<void>.delayed(const Duration(milliseconds: 1400));
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'No se pudo buscar el pedido: $error');
      await Future<void>.delayed(const Duration(milliseconds: 1400));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _manualEntry() async {
    final TextEditingController controller = TextEditingController();
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Buscar pedido'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Número de orden',
            hintText: 'MCA-000123',
          ),
          onSubmitted: (String text) =>
              Navigator.of(dialogContext).pop(text.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Buscar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty || !mounted) return;
    await _search(value);
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
      if (mounted) setState(() => _torchOn = !_torchOn);
    } catch (_) {
      // Algunos dispositivos no tienen linterna: se ignora sin romper el flujo.
    }
  }

  /// Pide a la cámara que enfoque el centro del marco.
  ///
  /// Es una acción real de `MobileScannerController.setFocusPoint`; el
  /// autoenfoque sigue activo y tocar la vista previa también enfoca. Nunca
  /// enciende ni apaga la linterna.
  Future<void> _focusCenter() async {
    if (!_controller.value.isRunning) return;
    try {
      await _controller.setFocusPoint(const Offset(0.5, 0.5));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          BarcodeScannerView(
            controller: _controller,
            formats: BarcodeScannerView.defaultQrFormats,
            onDetected: (String raw) => _onDetected(raw),
            overlay: const ColoredBox(color: Color(0x44000000)),
          ),
          SafeArea(
            child: Column(
              children: <Widget>[
                SizedBox(
                  height: 62,
                  child: Row(
                    children: <Widget>[
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 26,
                        ),
                        tooltip: 'Cerrar',
                      ),
                      const Expanded(
                        child: Text(
                          'Escanear pedido',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'LeagueSpartan',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _searching ? null : _manualEntry,
                        icon: const Icon(
                          Icons.keyboard_alt_outlined,
                          color: Colors.white,
                          size: 24,
                        ),
                        tooltip: 'Escribir número de orden',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Escanea el código QR\ndel pedido',
                  textAlign: TextAlign.center,
                  style: AppText.body(
                    20,
                    weight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.25,
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _searching
                                      ? AppColors.warning
                                      : Colors.white,
                                  width: 2.5,
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: <Widget>[
                      if (_searching)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      if (_message != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _message!,
                            textAlign: TextAlign.center,
                            style: AppText.body(13.5, color: Colors.white),
                          ),
                        ),
                      TextButton(
                        onPressed: _searching ? null : _manualEntry,
                        child: Text(
                          'Escribir número de orden',
                          style: AppText.body(
                            13,
                            weight: FontWeight.w600,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 6, 28, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      _ScannerAction(
                        icon: Icons.access_time,
                        label: 'Historial',
                        onTap: () =>
                            Navigator.of(context)
                                .pushNamed(StaffHistoryScreen.routeName),
                      ),
                      Tooltip(
                        message: 'Enfocar el código QR',
                        child: GestureDetector(
                          onTap: _searching ? null : _focusCenter,
                          child: Container(
                            width: 62,
                            height: 62,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.qr_code_scanner,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ),
                      ),
                      _ScannerAction(
                        icon: _torchOn
                            ? Icons.flashlight_on
                            : Icons.flashlight_off,
                        label: 'Linterna',
                        onTap: _toggleTorch,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerAction extends StatelessWidget {
  const _ScannerAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: Colors.white, size: 26),
            const SizedBox(height: 4),
            Text(label, style: AppText.body(12.5, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
