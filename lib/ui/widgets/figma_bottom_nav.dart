import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../screens/staff_history_screen.dart';
import '../screens/staff_home_screen.dart';
import '../screens/staff_reports_screen.dart';

/// Barra inferior del personal de caja (Órdenes · Historial · Reportes).
///
/// Es la misma barra en las tres pantallas: el elemento activo se pinta de
/// azul y el resto queda sobre el fondo lila, como en el diseño de Figma.
class StaffBottomNav extends StatelessWidget {
  const StaffBottomNav({
    super.key,
    required this.currentIndex,
  });

  /// 0 = Órdenes, 1 = Historial, 2 = Reportes.
  final int currentIndex;

  static const List<String> _labels = <String>[
    'Órdenes',
    'Historial',
    'Reportes',
  ];

  static const List<IconData> _icons = <IconData>[
    Icons.receipt_long_outlined,
    Icons.access_time,
    Icons.bar_chart,
  ];

  void _go(BuildContext context, int index) {
    if (index == currentIndex) return;
    final String route = switch (index) {
      1 => StaffHistoryScreen.routeName,
      2 => StaffReportsScreen.routeName,
      _ => StaffHomeScreen.routeName,
    };
    Navigator.of(context).pushNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Container(
        height: 72,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: AppColors.lilac,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: <Widget>[
            for (int i = 0; i < _labels.length; i++)
              Expanded(
                child: _NavItem(
                  label: _labels[i],
                  icon: _icons[i],
                  selected: i == currentIndex,
                  onTap: () => _go(context, i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                icon,
                size: 22,
                color: selected ? Colors.white : AppColors.textDark,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(
                  11.5,
                  weight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : AppColors.textDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
