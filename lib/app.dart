import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'core/theme/app_theme.dart';
import 'data/local/key_value_store.dart';
import 'data/models/admin_product.dart';
import 'data/models/product.dart';
import 'repositories/admin_catalog_repository.dart';
import 'repositories/cart_repository.dart';
import 'repositories/catalog_repository.dart';
import 'repositories/order_repository.dart';
import 'repositories/profile_repository.dart';
import 'repositories/scan_history_repository.dart';
import 'repositories/settings_repository.dart';
import 'repositories/staff_repository.dart';
import 'services/auth_service.dart';
import 'services/product_image_service.dart';
import 'services/supabase_service.dart';
import 'state/bootstrap_controller.dart';
import 'state/cart_controller.dart';
import 'state/catalog_controller.dart';
import 'state/order_controller.dart';
import 'state/order_history_controller.dart';
import 'state/origin_controller.dart';
import 'state/password_recovery_controller.dart';
import 'state/store_location_controller.dart';
import 'ui/screens/admin_barcodes_screen.dart';
import 'ui/screens/admin_codes_screen.dart';
import 'ui/screens/admin_panel_screen.dart';
import 'ui/screens/admin_product_form_screen.dart';
import 'ui/screens/admin_products_screen.dart';
import 'ui/screens/admin_promotions_screen.dart';
import 'ui/screens/admin_staff_screen.dart';
import 'ui/screens/admin_store_screen.dart';
import 'ui/screens/auth_gate.dart';
import 'ui/screens/bootstrap_screen.dart';
import 'ui/screens/camera_diagnostic_screen.dart';
import 'ui/screens/cart_screen.dart';
import 'ui/screens/catalog_screen.dart';
import 'ui/screens/category_products_screen.dart';
import 'ui/screens/enter_recovery_code_screen.dart';
import 'ui/screens/forgot_password_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/my_account_screen.dart';
import 'ui/screens/my_orders_screen.dart';
import 'ui/screens/order_detail_screen.dart';
import 'ui/screens/order_generated_screen.dart';
import 'ui/screens/product_detail_screen.dart';
import 'ui/screens/register_screen.dart';
import 'ui/screens/reset_password_screen.dart';
import 'ui/screens/scan_history_screen.dart';
import 'ui/screens/scanner_screen.dart';
import 'ui/screens/staff_history_screen.dart';
import 'ui/screens/staff_home_screen.dart';
import 'ui/screens/staff_reports_screen.dart';
import 'ui/screens/store_location_screen.dart';
import 'ui/screens/summary_screen.dart';

/// Raíz de la aplicación.
///
/// La interfaz se construye **inmediatamente**; el arranque (almacenamiento
/// local, servidor y sesión) ocurre después y se refleja en la pantalla de
/// arranque. Así la app nunca se queda en negro, ni aunque falte Internet, no
/// haya usuario, la tabla de tiendas esté vacía o no exista administrador.
class MercamigoApp extends StatefulWidget {
  const MercamigoApp({super.key});

  @override
  State<MercamigoApp> createState() => _MercamigoAppState();
}

class _MercamigoAppState extends State<MercamigoApp> {
  final BootstrapController _bootstrap = BootstrapController();

  /// Dependencias ya construidas (se crean una sola vez).
  _AppDependencies? _dependencies;

  /// `true` cuando ya se restauró el estado local.
  bool _localStateRestored = false;

  @override
  void initState() {
    super.initState();
    // El arranque se dispara aqui, pero la UI ya esta montada.
    _bootstrap.start();
  }

  @override
  void dispose() {
    _bootstrap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<BootstrapController>.value(
      value: _bootstrap,
      child: Consumer<BootstrapController>(
        builder: (BuildContext context, BootstrapController bootstrap, _) {
          _dependencies ??= _dependenciesFor(bootstrap);
          final _AppDependencies? dependencies = _dependencies;
          final bool ready = bootstrap.isReady && dependencies != null;

          if (ready && !_localStateRestored) {
            _localStateRestored = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              dependencies.restoreLocalState();
            });
          }

          Widget app = MaterialApp(
            title: 'Mercamigo',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(),
            home: ready
                ? const AuthGate()
                : BootstrapScreen(
                    stage: bootstrap.stage,
                    errorMessage: bootstrap.errorMessage,
                    errorDetails: bootstrap.errorDetails,
                    onRetry: bootstrap.retry,
                  ),
            onGenerateRoute: _onGenerateRoute,
          );

          if (dependencies != null) {
            app = MultiProvider(providers: dependencies.providers, child: app);
          }

          return app;
        },
      ),
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case LoginScreen.routeName:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const LoginScreen(),
          settings: settings,
        );
      case RegisterScreen.routeName:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const RegisterScreen(),
          settings: settings,
        );
      case ForgotPasswordScreen.routeName:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const ForgotPasswordScreen(),
          settings: settings,
        );
      case EnterRecoveryCodeScreen.routeName:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const EnterRecoveryCodeScreen(),
          settings: settings,
        );
      case ResetPasswordScreen.routeName:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const ResetPasswordScreen(),
          settings: settings,
        );
      case MyAccountScreen.routeName:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const MyAccountScreen(),
          settings: settings,
        );
      case MyOrdersScreen.routeName:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const MyOrdersScreen(),
          settings: settings,
        );
      case OrderDetailScreen.routeName:
        final Object? args = settings.arguments;
        if (args is! OrderDetailArgs) return null;
        return MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              OrderDetailScreen(order: args.order),
          settings: settings,
        );
      case AdminPanelScreen.routeName:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const AdminPanelScreen(),
          settings: settings,
        );
      case AdminProductsScreen.routeName:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const AdminProductsScreen(),
          settings: settings,
        );
      case AdminPromotionsScreen.routeName:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const AdminPromotionsScreen(),
          settings: settings,
        );
      case AdminProductFormScreen.routeName:
        final Object? args = settings.arguments;
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => AdminProductFormScreen(
            product: args is AdminProduct ? args : null,
          ),
          settings: settings,
        );
      case AdminCodesScreen.routeName:
        final Object? args = settings.arguments;
        return MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              AdminCodesScreen(productId: args is String ? args : null),
          settings: settings,
        );
      case AdminBarcodesScreen.routeName:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const AdminBarcodesScreen(),
          settings: settings,
        );
      case AdminStoreScreen.routeName:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const AdminStoreScreen(),
          settings: settings,
        );
      case AdminStaffScreen.routeName:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const AdminStaffScreen(),
          settings: settings,
        );
      case StaffHomeScreen.routeName:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const StaffHomeScreen(),
          settings: settings,
        );
      case StaffHistoryScreen.routeName:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const StaffHistoryScreen(),
          settings: settings,
        );
      case StaffReportsScreen.routeName:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const StaffReportsScreen(),
          settings: settings,
        );
      case HomeScreen.routeName:
      case '/':
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const HomeScreen(),
          settings: settings,
        );
      case CameraDiagnosticScreen.routeName:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const CameraDiagnosticScreen(),
          settings: settings,
        );
      case ScanHistoryScreen.routeName:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const ScanHistoryScreen(),
          settings: settings,
        );
      case ScannerScreen.routeName:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const ScannerScreen(),
          settings: settings,
        );
      case CatalogScreen.routeName:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const CatalogScreen(),
          settings: settings,
        );
      case CategoryProductsScreen.routeName:
        final Object? args = settings.arguments;
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => CategoryProductsScreen(
            args: args is CategoryProductsArgs
                ? args
                : const CategoryProductsArgs(),
          ),
          settings: settings,
        );
      case ProductDetailScreen.routeName:
        final Object? args = settings.arguments;
        if (args is! Product) return null;
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => ProductDetailScreen(product: args),
          settings: settings,
        );
      case CartScreen.routeName:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const CartScreen(),
          settings: settings,
        );
      case SummaryScreen.routeName:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const SummaryScreen(),
          settings: settings,
        );
      case OrderGeneratedScreen.routeName:
        final Object? args = settings.arguments;
        if (args is! OrderGeneratedArgs) return null;
        return MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              OrderGeneratedScreen(order: args.order),
          settings: settings,
        );
      case StoreLocationScreen.routeName:
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const StoreLocationScreen(),
          settings: settings,
        );
      default:
        return null;
    }
  }

  _AppDependencies? _dependenciesFor(BootstrapController bootstrap) {
    final KeyValueStore? store = bootstrap.store;
    final SupabaseService? supabase = bootstrap.supabase;
    final AuthService? auth = bootstrap.auth;
    if (store == null || supabase == null || auth == null) return null;
    return _AppDependencies(store: store, supabase: supabase, auth: auth);
  }
}

/// Repositorios y controladores de la app.
///
/// Se construyen una sola vez, cuando el arranque termina.
class _AppDependencies {
  _AppDependencies({
    required this.store,
    required this.supabase,
    required this.auth,
  }) : catalogRepository = CatalogRepository(
         store: store,
         client: supabase.client,
       ),
       cartRepository = CartRepository(store),
       orderRepository = OrderRepository(
         store: store,
         gateway: supabase.client == null
             ? null
             : SupabaseOrderGateway(supabase.client!),
         client: supabase.client,
       ),
       settingsRepository = SettingsRepository(
         store: store,
         client: supabase.client,
       ),
       profileRepository = ProfileRepository(client: supabase.client),
       scanHistoryRepository = ScanHistoryRepository(store: store);

  final KeyValueStore store;
  final SupabaseService supabase;
  final AuthService auth;

  final CatalogRepository catalogRepository;
  final CartRepository cartRepository;
  final OrderRepository orderRepository;
  final SettingsRepository settingsRepository;
  final ProfileRepository profileRepository;

  /// Historial de escaneos (local, separado por cuenta).
  final ScanHistoryRepository scanHistoryRepository;

  /// Acceso al catálogo en modo administrador.
  ///
  /// No comparte la caché del comprador: los productos inactivos no deben
  /// aparecerle al cliente.
  late final AdminCatalogRepository adminCatalogRepository =
      AdminCatalogRepository(client: supabase.client);

  /// Subida de las fotos de los productos a Supabase Storage.
  ///
  /// Sin servidor (`client == null`) el servicio avisa de que no se pueden
  /// subir fotos.
  late final ProductImageService productImageService = ProductImageService(
    client: supabase.client,
  );

  /// Acceso a las funciones de caja (RPC con autorización en el servidor).
  late final StaffRepository staffRepository = StaffRepository(
    client: supabase.client,
  );

  late final CartController cartController = CartController(
    cartRepository: cartRepository,
    catalogRepository: catalogRepository,
  );

  late final OriginController originController = OriginController(
    cartRepository: cartRepository,
  );

  late final CatalogController catalogController = CatalogController(
    catalogRepository: catalogRepository,
  );

  late final OrderController orderController = OrderController(
    orderRepository: orderRepository,
    settingsRepository: settingsRepository,
  );

  late final OrderHistoryController orderHistoryController =
      OrderHistoryController(repository: orderRepository);

  late final StoreLocationController storeLocationController =
      StoreLocationController(settingsRepository: settingsRepository);

  /// Flujo de cambio de contraseña con código de recuperación.
  late final PasswordRecoveryController passwordRecoveryController =
      PasswordRecoveryController(auth: auth);

  /// Proveedores para el árbol de widgets.
  late final List<SingleChildWidget> providers = <SingleChildWidget>[
    Provider<SupabaseService>.value(value: supabase),
    ChangeNotifierProvider<AuthService>.value(value: auth),
    Provider<CatalogRepository>.value(value: catalogRepository),
    Provider<AdminCatalogRepository>.value(value: adminCatalogRepository),
    Provider<StaffRepository>.value(value: staffRepository),
    Provider<ProfileRepository>.value(value: profileRepository),
    Provider<ScanHistoryRepository>.value(value: scanHistoryRepository),
    Provider<ProductImageService>.value(value: productImageService),
    ChangeNotifierProvider<CartController>.value(value: cartController),
    ChangeNotifierProvider<OriginController>.value(value: originController),
    ChangeNotifierProvider<CatalogController>.value(value: catalogController),
    ChangeNotifierProvider<OrderController>.value(value: orderController),
    ChangeNotifierProvider<OrderHistoryController>.value(
      value: orderHistoryController,
    ),
    ChangeNotifierProvider<StoreLocationController>.value(
      value: storeLocationController,
    ),
    ChangeNotifierProvider<PasswordRecoveryController>.value(
      value: passwordRecoveryController,
    ),
  ];

  /// Restaura el estado local una vez que las dependencias existen.
  Future<void> restoreLocalState() async {
    await Future.wait<void>(<Future<void>>[
      cartController.load(),
      originController.load(),
      orderController.load(),
      storeLocationController.load(),
      catalogController.refresh(),
    ]);
  }
}
