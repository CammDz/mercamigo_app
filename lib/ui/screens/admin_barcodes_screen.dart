import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/admin_product.dart';
import '../../repositories/admin_catalog_repository.dart';
import '../../services/barcode_service.dart';
import '../widgets/figma_header.dart';

/// Códigos de barras de los productos activos.
///
/// El código se dibuja **en el dispositivo** con Code 128, sin depender de una
/// Edge Function ni de Internet. El código que se muestra es el que el
/// servidor generó y guardó.
///
/// Permite buscar por nombre de producto o por código, y compartir la imagen
/// del código.
class AdminBarcodesScreen extends StatefulWidget {
  const AdminBarcodesScreen({super.key});

  static const String routeName = '/admin/codigos-barras';

  @override
  State<AdminBarcodesScreen> createState() => _AdminBarcodesScreenState();
}

class _AdminBarcodesScreenState extends State<AdminBarcodesScreen> {
  List<AdminProduct> _products = const <AdminProduct>[];
  bool _loading = true;
  String? _error;
  String _query = '';

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

  /// Productos activos que tienen algún código registrado.
  List<AdminProduct> get _productsWithCodes => _products
      .where(
        (AdminProduct product) => product.isActive && product.codes.isNotEmpty,
      )
      .toList(growable: false);

  /// Productos que coinciden con la búsqueda (por nombre o por código).
  List<AdminProduct> get _filtered {
    final String query = _query.trim().toLowerCase();
    final List<AdminProduct> base = _productsWithCodes;
    if (query.isEmpty) return base;
    return base
        .where((AdminProduct product) {
          if (product.name.toLowerCase().contains(query)) return true;
          return product.codes.any(
            (ProductCode code) => code.code.toLowerCase().contains(query),
          );
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final List<AdminProduct> items = _filtered;

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
            : Column(
                children: <Widget>[
                  _SearchField(
                    value: _query,
                    onChanged: (String value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _error != null
                        ? _ErrorView(message: _error!, onRetry: _load)
                        : items.isEmpty
                        ? _EmptyView(
                            searching: _query.trim().isNotEmpty,
                            total: _productsWithCodes.length,
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (BuildContext context, int index) =>
                                _BarcodeCard(product: items[index]),
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Buscador por nombre o código.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: TextField(
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Buscar por nombre o por código',
          prefixIcon: const Icon(Icons.search, color: AppColors.muted),
          suffixIcon: value.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, color: AppColors.muted),
                  onPressed: () => onChanged(''),
                ),
          isDense: true,
        ),
      ),
    );
  }
}

/// Tarjeta de un producto con su código de barras.
class _BarcodeCard extends StatefulWidget {
  const _BarcodeCard({required this.product});

  final AdminProduct product;

  @override
  State<_BarcodeCard> createState() => _BarcodeCardState();
}

class _BarcodeCardState extends State<_BarcodeCard> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _sharing = false;

  ProductCode? get _code {
    for (final ProductCode code in widget.product.codes) {
      if (code.isBarcode) return code;
    }
    return null;
  }

  Future<void> _share() async {
    if (_sharing) return;
    final ProductCode? code = _code;
    if (code == null) return;
    setState(() => _sharing = true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final RenderRepaintBoundary? boundary =
          _boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('El código todavía no está dibujado.');
      }
      final ui.Image image = await boundary.toImage(pixelRatio: 3);
      final ByteData? data = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      image.dispose();
      if (data == null || data.lengthInBytes == 0) {
        throw StateError('El código quedó vacío.');
      }
      await _shareImage(data.buffer.asUint8List(), code.code);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo compartir el código: $error')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _shareImage(Uint8List bytes, String code) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final ShareResultStatus status = await BarcodeShareService.shareBarcode(
      bytes: bytes,
      code: code,
    );
    if (status == ShareResultStatus.unavailable) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No hay ninguna app para compartir.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ProductCode? code = _code;
    final ProductCode? first = widget.product.codes.isEmpty
        ? null
        : widget.product.codes.first;
    if (first == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.grayBorder, width: 1.1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            widget.product.name,
            style: AppText.body(
              16,
              weight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Código: ${first.code}  ·  ${first.typeLabel}',
            style: AppText.body(13, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          RepaintBoundary(
            key: _boundaryKey,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: _BarcodeImage(code: first.code),
            ),
          ),
          const SizedBox(height: 10),
          if (code != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _sharing ? null : _share,
                icon: _sharing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.share_outlined, size: 18),
                label: Text('Compartir', style: AppText.body(13.5)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Imagen del código de barras, dibujada localmente.
class _BarcodeImage extends StatelessWidget {
  const _BarcodeImage({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    if (code.trim().isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Text(
          'Código no disponible',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.muted),
        ),
      );
    }

    return SizedBox(
      width: 300,
      child: BarcodeWidget(
        barcode: Barcode.code128(),
        data: code,
        height: 88,
        drawText: true,
        color: Colors.black,
        backgroundColor: Colors.white,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
          letterSpacing: 1,
        ),
        errorBuilder: (BuildContext context, String error) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Text(
            'No se pudo dibujar el código.',
            textAlign: TextAlign.center,
            style: AppText.body(13, color: AppColors.danger),
          ),
        ),
      ),
    );
  }
}

/// Error al cargar el catálogo.
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.cloud_off_outlined,
              size: 40,
              color: AppColors.danger,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppText.body(14, color: AppColors.danger),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sin resultados.
class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.searching, required this.total});

  final bool searching;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.view_week_outlined,
              size: 40,
              color: AppColors.muted,
            ),
            const SizedBox(height: 12),
            Text(
              searching
                  ? 'Ningún producto coincide con la búsqueda.'
                  : 'No hay productos con código registrado.',
              textAlign: TextAlign.center,
              style: AppText.body(14, color: AppColors.muted),
            ),
            if (!searching && total == 0) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Crea un producto para que el servidor le asigne su código.',
                textAlign: TextAlign.center,
                style: AppText.body(12.5, color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
