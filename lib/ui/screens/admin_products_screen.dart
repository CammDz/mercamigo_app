import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/money.dart';
import '../../data/models/admin_product.dart';
import '../../repositories/admin_catalog_repository.dart';
import '../widgets/figma_header.dart';
import '../widgets/primary_button.dart';
import 'admin_codes_screen.dart';
import 'admin_product_form_screen.dart';

/// Secciones visibles de la administración de productos.
enum AdminProductSection {
  /// Productos que se pueden comprar.
  activos,

  /// Productos desactivados (borrado lógico): no se pueden comprar.
  desactivados,
}

/// Administración de productos del administrador.
///
/// Dos secciones visibles (**Activos** y **Desactivados**) con el número de
/// productos de cada una. La búsqueda funciona dentro de la sección
/// seleccionada y los resultados se ven en esta misma pantalla.
///
/// Desactivar es un **borrado lógico** (`activo = false`): no se borra el
/// producto ni sus códigos y los pedidos históricos no se tocan.
class AdminProductsScreen extends StatefulWidget {
  const AdminProductsScreen({super.key});

  static const String routeName = '/admin/productos';

  @override
  State<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends State<AdminProductsScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<AdminProduct> _products = const <AdminProduct>[];

  AdminProductSection _section = AdminProductSection.activos;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() => setState(() {});

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

  /// Productos de la sección seleccionada (con los contadores).
  List<AdminProduct> get _sectionProducts => _products
      .where(
        (AdminProduct p) =>
            _section == AdminProductSection.activos ? p.isActive : !p.isActive,
      )
      .toList(growable: false);

  /// Productos visibles: sección + categoría + búsqueda.
  List<AdminProduct> get _visible {
    final String query = _searchController.text.trim().toLowerCase();
    return _sectionProducts
        .where((AdminProduct product) {
          if (query.isEmpty) return true;
          return product.name.toLowerCase().contains(query) ||
              product.categoryName.toLowerCase().contains(query) ||
              product.codesLabel.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _openForm({AdminProduct? product}) async {
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        settings: const RouteSettings(name: AdminProductFormScreen.routeName),
        builder: (BuildContext context) =>
            AdminProductFormScreen(product: product),
      ),
    );
    if (changed == true) await _load();
  }

  /// Activa o desactiva un producto (borrado lógico).
  Future<void> _toggleActive(AdminProduct product) async {
    final bool activating = !product.isActive;
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              activating ? 'Reactivar producto' : 'Desactivar producto',
              style: AppText.body(19, weight: FontWeight.w700),
            ),
            content: Text(
              activating
                  ? 'El producto volverá a aparecer en el catálogo y podrá '
                        'añadirse a nuevas compras.'
                  : 'El producto dejará de aparecer en el catálogo y no podrá '
                        'añadirse a nuevas compras. No se borra: sus códigos y '
                        'los pedidos que ya lo incluyen se conservan. Se puede '
                        'reactivar más tarde.',
              style: AppText.body(14.5, color: AppColors.muted),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('Cancelar', style: AppText.body(15)),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  activating ? 'Reactivar' : 'Desactivar',
                  style: AppText.body(
                    15,
                    weight: FontWeight.w700,
                    color: activating ? AppColors.success : AppColors.danger,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await context.read<AdminCatalogRepository>().setProductActive(
        id: product.id,
        active: activating,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            activating ? 'Producto reactivado.' : 'Producto desactivado.',
          ),
        ),
      );
      // Se recarga la lista: el producto cambia de sección y los
      // contadores se actualizan sin reiniciar la app.
      await _load();
    } on AdminCatalogException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<AdminProduct> products = _visible;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: FigmaHeader(
        title: 'Productos',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FigmaLabel('Buscar producto'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre o código',
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.cardBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.cardBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 20),
            // Las dos secciones visibles, con su número de productos.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _SectionTab(
                      label: 'Activos',
                      selected: _section == AdminProductSection.activos,
                      onTap: () => setState(
                        () => _section = AdminProductSection.activos,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SectionTab(
                      label: 'Desactivados',
                      selected: _section == AdminProductSection.desactivados,
                      onTap: () => setState(
                        () => _section = AdminProductSection.desactivados,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? _ErrorState(message: _error!, onRetry: _load)
                  : products.isEmpty
                  ? _EmptyState(section: _section)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      itemCount: products.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (BuildContext context, int index) {
                        final AdminProduct product = products[index];
                        return _ProductCard(
                          product: product,
                          busy: _busy,
                          onEdit: () => _openForm(product: product),
                          onToggle: () => _toggleActive(product),
                          onCodeTap: () => Navigator.of(context).pushNamed(
                            AdminCodesScreen.routeName,
                            arguments: product.id,
                          ),
                        );
                      },
                    ),
            ),
            if (!_loading &&
                _error == null &&
                _section == AdminProductSection.desactivados)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.lilac,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Los productos desactivados no aparecen en el catálogo. '
                    'Sus códigos y pedidos se conservan.',
                    style: AppText.body(
                      11.5,
                      color: AppColors.textDark,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _busy ? null : () => _openForm(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    '+ Crear producto',
                    style: AppText.body(14.5, weight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pestaña de sección (Activos / Desactivados).
class _SectionTab extends StatelessWidget {
  const _SectionTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.cardBorder,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(
              13,
              weight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.textDark,
            ),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de un producto en la administración.
class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.busy,
    required this.onEdit,
    required this.onToggle,
    required this.onCodeTap,
  });

  final AdminProduct product;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onCodeTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            product.name,
            style: AppText.body(
              16,
              weight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${product.categoryName} · ${formatCop(product.price)} COP',
            style: AppText.body(12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 3),
          InkWell(
            onTap: onCodeTap,
            child: Text(
              'Código: ${product.codesLabel}',
              style: AppText.body(11.5, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.cardBorder),
          Row(
            children: <Widget>[
              Expanded(
                child: InkWell(
                  onTap: onEdit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'Editar producto',
                      style: AppText.body(12, weight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              InkWell(
                onTap: busy ? null : onToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 8,
                  ),
                  child: Text(
                    product.isActive ? 'Desactivar' : 'Reactivar',
                    style: AppText.body(12, weight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Lista vacía de la sección.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.section});

  final AdminProductSection section;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              section == AdminProductSection.activos
                  ? Icons.inventory_2_outlined
                  : Icons.visibility_off_outlined,
              size: 52,
              color: AppColors.grayFill,
            ),
            const SizedBox(height: 12),
            Text(
              section == AdminProductSection.activos
                  ? 'No hay productos activos que coincidan.'
                  : 'No hay productos desactivados.',
              textAlign: TextAlign.center,
              style: AppText.body(14, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Error de carga con reintento.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppText.body(14, color: AppColors.danger),
            ),
            const SizedBox(height: 14),
            PrimaryButton.outlined(
              label: 'Reintentar',
              icon: Icons.refresh,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
