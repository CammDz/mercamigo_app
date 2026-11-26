import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Aviso de datos de demostración.
///
/// El catálogo de Mercamigo es un set de datos de prueba, así que la interfaz
/// lo indica de forma explícita en lugar de presentarlo como información real.
class DemoNotice extends StatelessWidget {
  const DemoNotice({
    super.key,
    this.text = 'Datos de demostración. No corresponden a productos reales.',
    this.icon = Icons.science_outlined,
    this.color = AppColors.warning,
  });

  final String text;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppText.body(13, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
