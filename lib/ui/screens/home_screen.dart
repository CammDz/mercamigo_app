import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/purchase_origin.dart';
import '../../state/origin_controller.dart';
import 'catalog_screen.dart';
import 'my_account_screen.dart';
import 'scanner_screen.dart';
import 'store_location_screen.dart';

/// Pantalla de bienvenida con las dos rutas de compra del diseño de Figma.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const String routeName = '/home';

  Future<void> _choose(BuildContext context, PurchaseOrigin origin) async {
    await context.read<OriginController>().setOrigin(origin);
    if (!context.mounted) return;
    switch (origin) {
      case PurchaseOrigin.inStore:
        await Navigator.of(context).pushNamed(ScannerScreen.routeName);
      case PurchaseOrigin.pickup:
        await Navigator.of(context).pushNamed(CatalogScreen.routeName);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double scale = math
              .min(
                1,
                math.min(
                  constraints.maxWidth / 360,
                  constraints.maxHeight / 800,
                ),
              )
              .toDouble();
          final double designWidth = 360 * scale;
          final double designHeight = 800 * scale;

          return SingleChildScrollView(
            child: SizedBox(
              width: constraints.maxWidth,
              height: math.max(constraints.maxHeight, designHeight).toDouble(),
              child: Center(
                child: SizedBox(
                  width: designWidth,
                  height: designHeight,
                  child: FittedBox(
                    fit: BoxFit.fill,
                    child: SizedBox(
                      width: 360,
                      height: 800,
                      child: Stack(
                        children: <Widget>[
                          const Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: <Color>[
                                    AppColors.primaryBright,
                                    AppColors.primaryDeep,
                                  ],
                                  stops: <double>[0, 1],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 106,
                            top: 17,
                            width: 147,
                            height: 131,
                            child: Image.asset(
                              'assets/figma/logo.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                          // Accesos discretos solicitados para cuenta y tienda.
                          Positioned(
                            left: 14,
                            top: 42,
                            child: _HomeIconButton(
                              icon: Icons.place_outlined,
                              label: 'Ubicación de la tienda',
                              onPressed: () =>
                                  Navigator.of(context)
                                      .pushNamed(StoreLocationScreen.routeName),
                            ),
                          ),
                          Positioned(
                            right: 14,
                            top: 42,
                            child: _HomeIconButton(
                              icon: Icons.person_outline,
                              label: 'Mi cuenta',
                              onPressed: () =>
                                  Navigator.of(context)
                                      .pushNamed(MyAccountScreen.routeName),
                            ),
                          ),
                          Positioned(
                            left: 23,
                            top: 161,
                            width: 313,
                            child: Text(
                              'MERCAMIGO',
                              textAlign: TextAlign.center,
                              style: AppText.display(
                                50,
                                weight: FontWeight.w400,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 23,
                            top: 237,
                            width: 313,
                            child: Text(
                              '¡Bienvenido!',
                              textAlign: TextAlign.center,
                              style: AppText.display(28, color: Colors.white),
                            ),
                          ),
                          Positioned(
                            left: 23,
                            top: 290,
                            width: 313,
                            child: Text(
                              'Elije como quieres\ncomprar hoy',
                              textAlign: TextAlign.center,
                              style: AppText.body(
                                28,
                                color: Colors.white,
                                height: 1,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 23,
                            top: 370,
                            width: 313,
                            height: 154,
                            child: _OriginCard(
                              title: 'Estoy en la tienda',
                              subtitle:
                                  'Escanea productos\ndesde los anaqueles',
                              iconAsset: 'assets/figma/icon_shop.png',
                              iconSize: 81,
                              onTap: () =>
                                  _choose(context, PurchaseOrigin.inStore),
                            ),
                          ),
                          Positioned(
                            left: 23,
                            top: 557,
                            width: 313,
                            height: 154,
                            child: _OriginCard(
                              title: 'Pedir desde\ndonde estes',
                              subtitle: 'Explora secciones y\nagrega tu orden',
                              iconAsset: 'assets/figma/icon_phone.png',
                              iconSize: 78,
                              onTap: () =>
                                  _choose(context, PurchaseOrigin.pickup),
                            ),
                          ),
                          const Positioned(
                            left: 40,
                            top: 739,
                            width: 280,
                            child: Text(
                              'Rapido ● Facil ● Sin Filas',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Roboto',
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HomeIconButton extends StatelessWidget {
  const _HomeIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: label,
      icon: Icon(icon, size: 24, color: Colors.white),
      style: IconButton.styleFrom(
        minimumSize: const Size(40, 40),
        padding: EdgeInsets.zero,
        backgroundColor: Colors.white.withValues(alpha: 0.12),
      ),
    );
  }
}

class _OriginCard extends StatelessWidget {
  const _OriginCard({
    required this.title,
    required this.subtitle,
    required this.iconAsset,
    required this.iconSize,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String iconAsset;
  final double iconSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: <Widget>[
              Image.asset(
                iconAsset,
                width: iconSize,
                height: iconSize,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppText.body(
                        23,
                        weight: FontWeight.w700,
                        color: AppColors.ink,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: AppText.body(
                        18,
                        color: AppColors.ink,
                        height: 1.05,
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
