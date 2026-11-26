import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/product.dart';
import '../../state/cart_controller.dart';
import '../../state/catalog_controller.dart';
import '../widgets/app_search_field.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/cart_badge_button.dart';
import '../widgets/demo_notice.dart';
import '../widgets/empty_state.dart';
import '../widgets/product_card.dart';
import 'cart_screen.dart';
import 'product_detail_screen.dart';

/// Argumentos de la pantalla de productos.
class CategoryProductsArgs {
  const CategoryProductsArgs({this.searchOnly = false, this.initialQuery = ''});

  /// `true` cuando se abre directamente desde la búsqueda del catálogo.
  final bool searchOnly;

  /// Texto inicial de la búsqueda.
  final String initialQuery;
}

/// Listado de productos de una categoría y resultados de la búsqueda global.
///
/// Cuando hay texto de búsqueda, los resultados provienen de **todo** el
/// catálogo (no solo de la categoría abierta).
class CategoryProductsScreen extends StatefulWidget {
  const CategoryProductsScreen({
    super.key,
    this.args = const CategoryProductsArgs(),
  });

  static const String routeName = '/products';

  final CategoryProductsArgs args;

  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  late final TextEditingController _searchController;

  /// Nodo de foco de la busqueda: al salir se quita el foco para que al
  /// volver a entrar el cursor no aparezca dentro de la barra de busqueda.
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.args.initialQuery);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final CatalogController catalog = context.read<CatalogController>();
      if (widget.args.initialQuery.isNotEmpty) {
        catalog.setQuery(widget.args.initialQuery);
      }
    });
  }

  @override
  void dispose() {
    _searchFocus.unfocus();
    _searchFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _addToCart(Product product) async {
    final CartController cart = context.read<CartController>();
    await cart.add(product);
    if (!mounted) return;
    await Navigator.of(context).pushNamed(CartScreen.routeName);
  }

  void _openDetail(Product product) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: ProductDetailScreen.routeName),
        builder: (BuildContext context) =>
            ProductDetailScreen(product: product),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final CatalogController catalog = context.watch<CatalogController>();
    final List<Product> products = catalog.visibleProducts;
    final String title = catalog.isSearching
        ? 'Resultados'
        : (catalog.category?.name ?? 'Todos los productos');

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppTopBar(
        title: title,
        titleStyle: AppText.body(25, weight: FontWeight.w600),
        onBack: () => Navigator.of(context).maybePop(),
        actions: const <Widget>[
          Padding(padding: EdgeInsets.only(right: 8), child: CartBadgeButton()),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double maxWidth = constraints.maxWidth >= 600 ? 620 : 460;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(25, 8, 25, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      AppSearchField(
                        controller: _searchController,
                        focusNode: _searchFocus,
                        onChanged: catalog.setQuery,
                        onSubmitted: (String value) {
                          catalog.setQuery(value);
                          _searchFocus.unfocus();
                        },
                      ),
                      const SizedBox(height: 12),
                      const SizedBox(height: 6),
                      if (products.isEmpty)
                        EmptyState(
                          icon: Icons.search_off,
                          title: catalog.isSearching
                              ? 'Sin resultados'
                              : 'Sin productos',
                          message: catalog.isSearching
                              ? 'No encontramos productos para "${catalog.query}". '
                                    'Prueba con otro nombre o categoría.'
                              : 'Esta categoría no tiene productos de demostración.',
                          actionLabel: catalog.isSearching
                              ? 'Limpiar búsqueda'
                              : null,
                          onAction: catalog.isSearching
                              ? () {
                                  _searchController.clear();
                                  catalog.setQuery('');
                                }
                              : null,
                        )
                      else
                        ...products.map(
                          (Product product) => ProductCard(
                            product: product,
                            onAdd: () => _addToCart(product),
                            onOpen: () => _openDetail(product),
                          ),
                        ),
                      const SizedBox(height: 12),
                      const DemoNotice(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
