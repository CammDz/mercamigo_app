import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/app_date_time.dart';
import '../../data/models/product.dart';
import '../../repositories/catalog_repository.dart';
import '../../repositories/scan_history_repository.dart';
import '../../services/auth_service.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/primary_button.dart';
import '../widgets/product_image.dart';
import 'product_detail_screen.dart';

/// Historial de **escaneos** del usuario.
///
/// Es distinto del historial de pedidos ("Mis pedidos"): aquí están los
/// productos que el usuario ha escaneado con la cámara, guardados solo en el
/// dispositivo y separados por cuenta.
class ScanHistoryScreen extends StatefulWidget {
  const ScanHistoryScreen({super.key});

  static const String routeName = '/escaneos';

  @override
  State<ScanHistoryScreen> createState() => _ScanHistoryScreenState();
}

class _ScanHistoryScreenState extends State<ScanHistoryScreen> {
  List<ScanHistoryEntry> _entries = const <ScanHistoryEntry>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final ScanHistoryRepository repository = context
        .read<ScanHistoryRepository>();
    final List<ScanHistoryEntry> entries = await repository.load(
      userKey(context),
    );
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  /// Clave por cuenta: los escaneos no se mezclan entre usuarios.
  static String userKey(BuildContext context) {
    final String? email = context.read<AuthService>().email;
    return email ?? 'anon';
  }

  Future<void> _clear() async {
    final ScanHistoryRepository repository = context
        .read<ScanHistoryRepository>();
    await repository.clear(userKey(context));
    if (!mounted) return;
    setState(() => _entries = const <ScanHistoryEntry>[]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppTopBar(
        title: 'Escaneos recientes',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _entries.isEmpty
            ? const _EmptyHistory()
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
                itemCount: _entries.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (BuildContext context, int index) {
                  if (index == _entries.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: PrimaryButton.outlined(
                        label: 'Borrar historial',
                        icon: Icons.delete_outline,
                        foregroundColor: AppColors.danger,
                        onPressed: _clear,
                      ),
                    );
                  }
                  return _ScanTile(entry: _entries[index]);
                },
              ),
      ),
    );
  }
}

/// Fila de un escaneo.
class _ScanTile extends StatelessWidget {
  const _ScanTile({required this.entry});

  final ScanHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final Product? product = context.read<CatalogRepository>().byId(
      entry.productId,
    );

    return InkWell(
      onTap: product == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => ProductDetailScreen(
                  product: product,
                  origin: 'Escaneos recientes',
                ),
              ),
            ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: <Widget>[
            _HistoryImage(product: product, imageUrl: entry.imageUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    entry.productName,
                    style: AppText.body(
                      15,
                      weight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Código ${entry.code}',
                    style: AppText.body(12.5, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            Text(
              _formatDate(entry.scannedAt),
              style: AppText.body(11.5, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  /// Fecha y hora del escaneo, siempre en hora de Bogota.
  static String _formatDate(DateTime date) => formatBogotaShortDateTime(date);
}

class _HistoryImage extends StatelessWidget {
  const _HistoryImage({required this.product, required this.imageUrl});

  final Product? product;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    if (product != null) {
      return ProductImage(product: product!, size: 48, borderRadius: 10);
    }
    final String? url = imageUrl;
    if (url != null && url.isNotEmpty) {
      final Widget image = url.startsWith('assets/')
          ? Image.asset(
              url,
              width: 48,
              height: 48,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => _fallback(),
            )
          : Image.network(
              url,
              width: 48,
              height: 48,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => _fallback(),
            );
      return ClipRRect(borderRadius: BorderRadius.circular(10), child: image);
    }
    return _fallback();
  }

  Widget _fallback() => Container(
    width: 48,
    height: 48,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.surfaceSoft,
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Icon(Icons.shopping_basket_outlined, color: AppColors.muted),
  );
}

/// Estado vacío del historial de escaneos.
class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.view_week_outlined,
              size: 58,
              color: AppColors.grayFill,
            ),
            const SizedBox(height: 14),
            Text(
              'Todavía no has escaneado ningún producto.',
              textAlign: TextAlign.center,
              style: AppText.body(14, color: AppColors.muted),
            ),
            const SizedBox(height: 8),
            Text(
              'Los productos que escanees aparecerán aquí.',
              textAlign: TextAlign.center,
              style: AppText.body(12.5, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
