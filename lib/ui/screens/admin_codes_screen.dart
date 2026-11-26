import 'package:barcode_widget/barcode_widget.dart' as barcode;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/admin_product.dart';
import '../../repositories/admin_catalog_repository.dart';
import '../widgets/figma_header.dart';
import '../widgets/barcode_scanner_view.dart';
import '../widgets/primary_button.dart';

/// Administración de los códigos de barras de los productos.
///
/// Permite:
/// · Escanear el código del empaque con la cámara.
/// · Introducirlo a mano.
/// · Asociarlo al producto correcto.
/// · Ver los códigos de cada producto.
///
/// El **código principal** lo genera el servidor al crear el producto y no se
/// edita. Aquí solo se agregan códigos **adicionales** (por ejemplo, códigos
/// de distintos empaques); el servidor rechaza los duplicados.
///
/// Registrar un código NO crea el producto: el administrador debe asociarlo
/// al catálogo desde la pantalla de productos.
class AdminCodesScreen extends StatefulWidget {
  const AdminCodesScreen({super.key, this.productId});

  static const String routeName = '/admin/codigos';

  /// Si viene informado, se abre filtrado por ese producto.
  final String? productId;

  @override
  State<AdminCodesScreen> createState() => _AdminCodesScreenState();
}

class _AdminCodesScreenState extends State<AdminCodesScreen> {
  List<AdminProduct> _products = const <AdminProduct>[];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final AdminCatalogSnapshot snapshot = await context
          .read<AdminCatalogRepository>()
          .load();
      if (!mounted) return;
      setState(() {
        _products = snapshot.products;
        _loading = false;
      });
    } on AdminCatalogException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el catálogo: $error';
        _loading = false;
      });
    }
  }

  List<AdminProduct> get _visible {
    final String? productId = widget.productId;
    if (productId == null) return _products;
    return _products
        .where((AdminProduct product) => product.id == productId)
        .toList(growable: false);
  }

  Future<void> _register(AdminProduct product) async {
    final _CodeDraft? draft = await showModalBottomSheet<_CodeDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => _RegisterCodeSheet(product: product),
    );
    if (draft == null || !mounted) return;
    await _saveCode(product, draft.code);
  }

  Future<void> _scanAndRegister(AdminProduct product) async {
    final String? code = await _scanCodeWithCamera(context);
    if (code == null || !mounted) return;
    await _saveCode(product, code);
  }

  Future<void> _saveCode(AdminProduct product, String code) async {
    setState(() => _busy = true);
    try {
      await context.read<AdminCatalogRepository>().registerCode(
        productId: product.id,
        code: code,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Código adicional registrado.')),
      );
      await _load();
    } on AdminCatalogException catch (error) {
      if (!mounted) return;
      _showError(error.message);
    } catch (error) {
      if (!mounted) return;
      _showError('No se pudo registrar el código: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<AdminProduct> products = _visible;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: FigmaHeader(
        title: 'Códigos de barras',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: AppText.body(14, color: AppColors.danger),
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                itemCount: products.length,
                separatorBuilder: (_, _) => const SizedBox(height: 20),
                itemBuilder: (BuildContext context, int index) {
                  final AdminProduct product = products[index];
                  return _ProductCodesCard(
                    product: product,
                    busy: _busy,
                    onScan: () => _scanAndRegister(product),
                    onWrite: () => _register(product),
                  );
                },
              ),
      ),
    );
  }
}

/// Datos de un código introducido por el administrador.
class _CodeDraft {
  const _CodeDraft({required this.code});

  final String code;
}

/// Hoja para registrar un código nuevo.
class _RegisterCodeSheet extends StatefulWidget {
  const _RegisterCodeSheet({required this.product});

  final AdminProduct product;

  @override
  State<_RegisterCodeSheet> createState() => _RegisterCodeSheetState();
}

class _RegisterCodeSheetState extends State<_RegisterCodeSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final String? scanned = await _scanCodeWithCamera(context);
    if (scanned == null) return;
    setState(() => _controller.text = scanned);
  }

  void _submit() {
    final String code = _controller.text.trim();
    if (code.isEmpty) return;
    Navigator.of(context).pop(_CodeDraft(code: code));
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'Agregar código adicional',
      subtitle: widget.product.name,
      children: <Widget>[
        TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Código de barras adicional',
            hintText: 'Se conserva tal cual, con sus ceros',
          ),
        ),
        const SizedBox(height: 16),
        PrimaryButton.outlined(
          label: 'Escanear con la cámara',
          icon: Icons.qr_code_scanner,
          onPressed: _scan,
        ),
        const SizedBox(height: 10),
        PrimaryButton(
          label: 'Registrar código adicional',
          icon: Icons.save_outlined,
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// Marco común de las hojas de códigos.
class _SheetShell extends StatelessWidget {
  const _SheetShell({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(title, style: AppText.body(19, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle, style: AppText.body(13, color: AppColors.muted)),
                const SizedBox(height: 18),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta con los códigos de un producto.
class _ProductCodesCard extends StatelessWidget {
  const _ProductCodesCard({
    required this.product,
    required this.busy,
    required this.onScan,
    required this.onWrite,
  });

  final AdminProduct product;
  final bool busy;
  final VoidCallback onScan;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    final String primaryCode = product.codes.isEmpty
        ? 'Sin código'
        : product.codes.first.code;
    final List<ProductCode> extra = product.codes.length > 1
        ? product.codes.sublist(1)
        : const <ProductCode>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(product.name, style: AppText.body(18, weight: FontWeight.w700)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (product.codes.isNotEmpty)
                barcode.BarcodeWidget(
                  barcode: barcode.Barcode.code128(),
                  data: primaryCode,
                  height: 64,
                  drawText: false,
                  color: Colors.black,
                  backgroundColor: Colors.white,
                  errorBuilder: (_, _) => const SizedBox(
                    height: 64,
                    child: Center(child: Text('No se pudo dibujar el código.')),
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                primaryCode,
                style: AppText.body(16, weight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                'Generado por Supabase · Solo lectura',
                style: AppText.body(11, color: AppColors.textMuted),
              ),
              if (extra.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                for (final ProductCode code in extra)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Adicional: ${code.code}',
                      style: AppText.body(11.5, color: AppColors.textMuted),
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Añadir otro código',
          style: AppText.body(14.5, weight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Asocia un código de barras del empaque.',
          style: AppText.body(12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 46,
          child: FilledButton(
            onPressed: busy ? null : onScan,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Escanear con la cámara',
              style: AppText.body(13.5, weight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 46,
          child: FilledButton(
            onPressed: busy ? null : onWrite,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.lilac,
              foregroundColor: AppColors.textDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Escribir código',
              style: AppText.body(13.5, weight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.lilac,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'Cada código debe ser único. Si ya pertenece a otro producto, '
            'no se podrá guardar.',
            style: AppText.body(11.5, color: AppColors.textDark, height: 1.35),
          ),
        ),
      ],
    );
  }
}

/// Abre la cámara y devuelve el código leído (o `null` si se cancela).
Future<String?> _scanCodeWithCamera(BuildContext context) async {
  final MobileScannerController controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: BarcodeScannerView.defaultBarcodeFormats,
  );
  final String? result = await Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      fullscreenDialog: true,
      builder: (BuildContext context) =>
          _CameraScanPage(controller: controller),
    ),
  );
  await controller.dispose();
  return result;
}

/// Página a pantalla completa con la cámara para leer un código.
class _CameraScanPage extends StatelessWidget {
  const _CameraScanPage({required this.controller});

  final MobileScannerController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          BarcodeScannerView(
            controller: controller,
            onDetected: (String code) => Navigator.of(context).pop(code),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white, size: 26),
                tooltip: 'Cerrar',
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: Text(
                  'Apunta al código de barras del empaque',
                  style: AppText.body(14, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
