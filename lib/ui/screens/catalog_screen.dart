import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/money.dart';
import '../../data/models/product.dart';
import '../../data/models/product_category.dart';
import '../../state/cart_controller.dart';
import '../../state/catalog_controller.dart';
import '../widgets/app_search_field.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/cart_badge_button.dart';
import '../widgets/demo_notice.dart';
import '../widgets/empty_state.dart';
import '../widgets/product_card.dart';
import '../widgets/product_image.dart';
import '../widgets/primary_button.dart';
import 'cart_screen.dart';
import 'category_products_screen.dart';
import 'product_detail_screen.dart';

/// Cabecera de los resultados de búsqueda (en la misma pantalla).
class _SearchResultsHeader extends StatelessWidget {
  const _SearchResultsHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Icon(Icons.public, size: 16, color: AppColors.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Buscando en todo el catálogo ($count resultado(s))',
            style: AppText.body(13, color: AppColors.muted),
          ),
        ),
      ],
    );
  }
}

/// Catálogo digital: categorías, promociones y búsqueda en la misma pantalla.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  static const String routeName = '/catalog';

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final TextEditingController _searchController = TextEditingController();

  /// Nodo de foco de la busqueda.
  ///
  /// Al salir de la pantalla se quita el foco y se limpia la consulta: si no,
  /// al volver a entrar el cursor aparece dentro de la barra de busqueda.
  final FocusNode _searchFocus = FocusNode();

  /// Catalogo global (se guarda para poder limpiar la busqueda al salir).
  CatalogController? _catalog;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _catalog ??= context.read<CatalogController>();
  }

  @override
  void dispose() {
    _searchFocus.unfocus();
    _searchFocus.dispose();
    _searchController.dispose();
    // La busqueda no sobrevive a la pantalla: al volver a entrar se ve el
    // catalogo completo, no los resultados del ultimo texto buscado.
    _catalog?.setQuery('');
    super.dispose();
  }

  void _openCategory(ProductCategory category) {
    context.read<CatalogController>().setCategory(category);
    Navigator.of(context).pushNamed(
      CategoryProductsScreen.routeName,
      arguments: const CategoryProductsArgs(),
    );
  }

  /// Añade un producto al carrito desde los resultados de la búsqueda.
  Future<void> _addToCart(Product product) async {
    final CartController cart = context.read<CartController>();
    await cart.add(product);
    if (!mounted) return;
    await Navigator.of(context).pushNamed(CartScreen.routeName);
  }

  /// Abre el detalle de un producto de los resultados.
  Future<void> _openDetail(Product product) async {
    await Navigator.of(context).push(
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
    final List<Product> promoProducts = catalog.productsWithPromotion;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppTopBar(
        title: 'Catálogo',
        titleStyle: AppText.body(25, weight: FontWeight.w600),
        leadingIcon: Icons.close,
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
                        hintText: 'Buscar Productos....',
                        // La búsqueda se hace **aquí**: no se abre ninguna
                        // otra pantalla. Los resultados sustituyen el
                        // contenido del catálogo mientras hay texto.
                        onChanged: catalog.setQuery,
                        onSubmitted: (String value) {
                          catalog.setQuery(value);
                          // Al terminar la busqueda el campo suelta el foco.
                          _searchFocus.unfocus();
                        },
                      ),
                      const SizedBox(height: 18),
                      if (catalog.isSearching) ...<Widget>[
                        _SearchResultsHeader(
                          count: catalog.searchResults.length,
                        ),
                        const SizedBox(height: 12),
                        if (catalog.searchResults.isEmpty)
                          EmptyState(
                            icon: Icons.search_off,
                            title: 'Sin resultados',
                            message:
                                'No encontramos productos para '
                                '"${catalog.query}". Prueba con otro nombre '
                                'o categoría.',
                            actionLabel: 'Limpiar búsqueda',
                            onAction: () {
                              _searchController.clear();
                              catalog.setQuery('');
                            },
                          )
                        else
                          ...catalog.searchResults.map(
                            (Product product) => ProductCard(
                              product: product,
                              onAdd: () => _addToCart(product),
                              onOpen: () => _openDetail(product),
                            ),
                          ),
                        const SizedBox(height: 18),
                      ] else ...<Widget>[
                        if (catalog.isEmpty)
                          _CatalogUnavailable(
                            isLoading: catalog.isLoading,
                            error: catalog.lastError,
                            onRetry: () => catalog.refresh(),
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              'Categorias',
                              style: AppText.body(19, weight: FontWeight.w600),
                            ),
                            TextButton(
                              onPressed: () {
                                catalog.setCategory(null);
                                Navigator.of(context).pushNamed(
                                  CategoryProductsScreen.routeName,
                                  arguments: const CategoryProductsArgs(),
                                );
                              },
                              child: Text(
                                'Ver todas',
                                style: AppText.body(
                                  15,
                                  weight: FontWeight.w600,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _CategoryGrid(
                          categories: catalog.categories,
                          onTap: _openCategory,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Promociones',
                          style: AppText.body(19, weight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        if (promoProducts.isEmpty)
                          _NoPromotions()
                        else if (promoProducts.length > 2)
                          _PromoCarousel(products: promoProducts)
                        else
                          ...promoProducts.map(
                            (Product product) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _PromoBanner(product: product),
                            ),
                          ),
                        const SizedBox(height: 14),
                        const DemoNotice(
                          text:
                              'El catálogo de la base de datos es de '
                              'demostración: precios y existencias no '
                              'corresponden a un inventario real.',
                        ),
                      ],
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

/// Al superar dos promociones, las presenta en un carrusel que avanza solo
/// y también permite cambiar de banner con un gesto.
class _PromoCarousel extends StatefulWidget {
  const _PromoCarousel({required this.products});

  final List<Product> products;

  @override
  State<_PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<_PromoCarousel> {
  late final PageController _pageController;
  Timer? _timer;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startAutoScroll();
  }

  @override
  void didUpdateWidget(covariant _PromoCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.products.length != widget.products.length) {
      _currentPage = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
      });
    }
  }

  void _startAutoScroll() {
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_pageController.hasClients) return;
      final int nextPage = (_currentPage + 1) % widget.products.length;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        SizedBox(
          height: 135,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.products.length,
            onPageChanged: (int page) => setState(() => _currentPage = page),
            itemBuilder: (BuildContext context, int index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: _PromoBanner(product: widget.products[index]),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: 'Promoción ${_currentPage + 1} de ${widget.products.length}',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(widget.products.length, (
              int index,
            ) {
              final bool selected = index == _currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: selected ? 18 : 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : AppColors.grayStroke,
                  borderRadius: BorderRadius.circular(8),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

/// Banner promocional del catálogo.
class _PromoBanner extends StatelessWidget {
  const _PromoBanner({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final promotion = product.promotion!;
    final String title = promotion.type.name == 'bundlePrice'
        ? '${promotion.bundleQuantity}x${formatCopUnit(promotion.bundlePrice ?? 0)}'
        : promotion.title;

    return Container(
      height: 135,
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(28),
        image: promotion.bannerImageUrl == null
            ? null
            : DecorationImage(
                image: NetworkImage(promotion.bannerImageUrl!),
                fit: BoxFit.cover,
                colorFilter: const ColorFilter.mode(
                  Color(0x66000000),
                  BlendMode.darken,
                ),
              ),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x445D9EF3), blurRadius: 5, spreadRadius: 1),
        ],
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  title,
                  style: AppText.body(
                    32,
                    weight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(14, color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  promotion.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(13, color: Colors.white),
                ),
              ],
            ),
          ),
          if (promotion.bannerImageUrl == null)
            SizedBox(
              width: 110,
              child: ProductImage(product: product, size: 110, borderRadius: 8),
            ),
        ],
      ),
    );
  }
}

/// Aviso cuando el catálogo no se pudo cargar.
class _CatalogUnavailable extends StatelessWidget {
  const _CatalogUnavailable({
    required this.isLoading,
    required this.error,
    required this.onRetry,
  });

  final bool isLoading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            isLoading
                ? 'Cargando catálogo...'
                : 'No se pudo cargar el catálogo',
            style: AppText.body(16, weight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            error ??
                'Conéctate a internet la primera vez para descargar el '
                    'catálogo de la tienda. Después queda disponible sin '
                    'conexión.',
            style: AppText.body(13, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            label: 'Reintentar',
            icon: Icons.refresh,
            height: 46,
            isLoading: isLoading,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

/// Aviso cuando el catálogo no tiene promociones configuradas.
class _NoPromotions extends StatelessWidget {
  const _NoPromotions();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.local_offer_outlined, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No hay promociones configuradas en el catálogo.',
              style: AppText.body(14, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cuadrícula de categorías con los íconos circulares del prototipo.
class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.categories, required this.onTap});

  final List<ProductCategory> categories;
  final ValueChanged<ProductCategory> onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 14,
        crossAxisSpacing: 6,
        childAspectRatio: 0.82,
      ),
      itemCount: categories.length,
      itemBuilder: (BuildContext context, int index) {
        final ProductCategory category = categories[index];
        return InkWell(
          onTap: () => onTap(category),
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                height: 63,
                width: 63,
                decoration: BoxDecoration(
                  color: AppColors.grayFill,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.grayStroke, width: 2),
                ),
                padding: const EdgeInsets.all(9),
                child: Image.asset(
                  category.iconAsset,
                  fit: BoxFit.contain,
                  errorBuilder: (
                    BuildContext context,
                    Object error,
                    StackTrace? stack,
                  ) => Icon(Icons.category, size: 26, color: category.color),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                category.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(13, color: AppColors.ink),
              ),
            ],
          ),
        );
      },
    );
  }
}
