import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Cabecera de pantalla con flecha de retroceso, título y acciones.
///
/// Reproduce la cabecera del prototipo (fondo blanco, icono oscuro a la
/// izquierda, título centrado y carrito a la derecha con contador).
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    required this.title,
    this.onBack,
    this.actions = const <Widget>[],
    this.titleColor = AppColors.ink,
    this.titleStyle,
    this.backgroundColor = AppColors.surface,
    this.leadingIcon = Icons.arrow_back,
    this.showBack = true,
  });

  final String title;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final Color titleColor;
  final TextStyle? titleStyle;
  final Color backgroundColor;

  /// Icono de la izquierda. El catálogo usa una X de cierre.
  final IconData leadingIcon;

  /// `false` para pantallas sin acción de volver.
  final bool showBack;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: backgroundColor,
      automaticallyImplyLeading: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 0,
      leading: !showBack
          ? null
          : IconButton(
              icon: Icon(leadingIcon, color: AppColors.ink),
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              tooltip: 'Volver',
            ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style:
            titleStyle ??
            AppText.body(22, weight: FontWeight.w700, color: titleColor),
      ),
      actions: actions,
      centerTitle: true,
    );
  }
}
