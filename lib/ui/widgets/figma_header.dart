import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Cabecera azul del rediseño de Figma.
///
/// Reproduce la barra azul, la flecha oscura y el título negro que comparten
/// las pantallas interiores (productos, órdenes,
/// reportes, administración…).
class FigmaHeader extends StatelessWidget implements PreferredSizeWidget {
  const FigmaHeader({
    super.key,
    required this.title,
    this.onBack,
    this.actions = const <Widget>[],
    this.showBack = true,
    this.centerTitle = false,
  });

  final String title;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final bool showBack;
  final bool centerTitle;

  @override
  Size get preferredSize => const Size.fromHeight(44);

  @override
  Widget build(BuildContext context) {
    final double top = MediaQuery.paddingOf(context).top;
    return Container(
      decoration: const BoxDecoration(color: AppColors.primary),
      padding: EdgeInsets.only(top: top),
      child: SizedBox(
        height: 44,
        child: Row(
          children: <Widget>[
            if (showBack)
              SizedBox(
                width: 60,
                child: IconButton(
                  onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back, color: AppColors.textDark),
                  iconSize: 26,
                  tooltip: 'Volver',
                ),
              )
            else
              const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: centerTitle ? TextAlign.center : TextAlign.start,
                style: AppText.body(
                  22,
                  weight: FontWeight.w700,
                  color: AppColors.textDark,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            ...actions,
            if (actions.isEmpty) const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}

/// Fondo gris claro de las pantallas interiores.
class FigmaBackground extends StatelessWidget {
  const FigmaBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: AppColors.background, child: child);
  }
}

/// Tarjeta blanca redondeada con borde suave, como en Figma.
class FigmaCard extends StatelessWidget {
  const FigmaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.color = Colors.white,
    this.borderColor = AppColors.cardBorder,
    this.radius = 16,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color color;
  final Color borderColor;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final BorderRadius shape = BorderRadius.circular(radius);
    final Widget content = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: shape,
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: shape, child: content),
    );
  }
}

/// Chip de filtro del rediseño: azul cuando está activo, lila cuando no.
class FigmaChip extends StatelessWidget {
  const FigmaChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Número opcional que se muestra junto a la etiqueta ("Pendientes · 3").
  final int? count;

  @override
  Widget build(BuildContext context) {
    final String text = count == null ? label : '$label · $count';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.lilac,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(
              12.5,
              weight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.textDark,
            ),
          ),
        ),
      ),
    );
  }
}

/// Etiqueta pequeña de sección ("Buscar producto", "Periodo"…).
class FigmaLabel extends StatelessWidget {
  const FigmaLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppText.body(
        13,
        weight: FontWeight.w600,
        color: AppColors.textDark,
      ),
    );
  }
}
