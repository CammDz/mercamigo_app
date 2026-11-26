import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../services/auth_service.dart';
import '../widgets/figma_header.dart';
import 'admin_products_screen.dart';
import 'admin_promotions_screen.dart';
import 'admin_store_screen.dart';
import 'my_account_screen.dart';

/// Inicio de la interfaz de **administración**.
///
/// El administrador no ve el inicio de compra: entra en su propia pantalla,
/// con accesos a productos, tienda y cuenta. Los accesos de códigos y personal
/// de caja se conservan como funciones existentes.
///
/// Ocultar la pantalla no es una medida de autorización: todas las acciones
/// se comprueban en el servidor (ver `public.es_administrador()`).
class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  static const String routeName = '/admin';

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  /// `true` mientras se cierra la sesión (evita pulsaciones duplicadas).
  bool _signingOut = false;

  /// Cierra la sesión y vuelve al inicio de sesión.
  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);

    final AuthService auth = context.read<AuthService>();
    // El aviso global (el de la app) sobrevive a la navegacion.
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(
      Navigator.of(context, rootNavigator: true).context,
    );

    // 1) Cierre de sesion local **inmediato**: se manda al login sin esperar
    //    a que el servidor revoque el token.
    final Future<SignOutResult> closing = auth.signOut();

    // 2) Al login, eliminando las rutas protegidas del historial.
    if (mounted) {
      Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
    }

    // 3) El aviso de errores sigue en segundo plano.
    final SignOutResult result = await closing;
    if (!result.sessionClosed) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No se pudo cerrar la sesion. Intentalo de nuevo.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AuthService auth = context.watch<AuthService>();

    if (!auth.isAdmin) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: FigmaHeader(
          title: 'ADMINISTRACIÓN',
          onBack: () => Navigator.of(context).maybePop(),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text(
              'Tu cuenta no tiene el rol de administrador. '
              'El permiso se comprueba en el servidor.',
              textAlign: TextAlign.center,
              style: AppText.body(15, color: AppColors.textMuted),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: FigmaHeader(
        title: 'Administración',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double maxWidth = constraints.maxWidth >= 600 ? 560 : 460;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 48,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Image.asset(
                                'assets/figma/logo.png',
                                width: 60,
                                height: 54,
                                fit: BoxFit.contain,
                                errorBuilder:
                                    (
                                      BuildContext context,
                                      Object error,
                                      StackTrace? stack,
                                    ) => const Icon(
                                      Icons.shopping_basket_outlined,
                                      size: 54,
                                      color: AppColors.primary,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Tu negocio, en un lugar',
                              style: AppText.body(22, weight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Gestiona productos, tienda y cuenta.',
                              style: AppText.body(
                                13,
                                color: AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(height: 26),
                            _AdminEntry(
                              icon: Icons.receipt_long_outlined,
                              title: 'Productos',
                              subtitle: 'Crea, edita y organiza tu catálogo.',
                              onTap: () =>
                                  Navigator.of(context)
                                      .pushNamed(AdminProductsScreen.routeName),
                            ),
                            const SizedBox(height: 20),
                            _AdminEntry(
                              icon: Icons.local_offer_outlined,
                              title: 'Promociones',
                              subtitle:
                                  'Crea ofertas para productos y banners.',
                              onTap: () => Navigator.of(context)
                                  .pushNamed(AdminPromotionsScreen.routeName),
                            ),
                            const SizedBox(height: 20),
                            _AdminEntry(
                              icon: Icons.storefront_outlined,
                              title: 'Tienda',
                              subtitle: 'Configura los datos y la ubicación.',
                              onTap: () =>
                                  Navigator.of(context)
                                      .pushNamed(AdminStoreScreen.routeName),
                            ),
                            const SizedBox(height: 20),
                            _AdminEntry(
                              icon: Icons.person_outline,
                              title: 'Mi cuenta',
                              subtitle: 'Revisa tus datos y tu sesión.',
                              onTap: () =>
                                  Navigator.of(context)
                                      .pushNamed(MyAccountScreen.routeName),
                            ),
                          ],
                        ),
                        SizedBox(
                          height: 50,
                          child: FilledButton(
                            onPressed: _signingOut ? null : _signOut,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.lilac,
                              foregroundColor: AppColors.textDark,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _signingOut
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                    ),
                                  )
                                : Text(
                                    'Cerrar sesión',
                                    style: AppText.body(
                                      14.5,
                                      weight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
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

/// Tarjeta de acceso del panel administrativo.
class _AdminEntry extends StatelessWidget {
  const _AdminEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.lilac,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.textDark, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      style: AppText.body(
                        16,
                        weight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: AppText.body(
                        12.5,
                        color: AppColors.textMuted,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
