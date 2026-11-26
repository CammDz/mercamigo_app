import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Control de cantidad usado en el detalle de producto.
///
/// Reproduce el patrón del prototipo: una barra clara con un círculo gris a
/// cada lado (menos / más) y la cantidad en el centro.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.quantity,
    required this.onDecrease,
    required this.onIncrease,
    this.canDecrease = true,
    this.canIncrease = true,
    this.barColor = const Color(0xFFE6EDF8),
  });

  final int quantity;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final bool canDecrease;
  final bool canIncrease;
  final Color barColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 61,
      decoration: BoxDecoration(
        color: barColor,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: <Widget>[
          _RoundButton(
            icon: Icons.remove,
            enabled: canDecrease,
            onPressed: onDecrease,
          ),
          Expanded(
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: AppText.body(20, weight: FontWeight.w800),
            ),
          ),
          _RoundButton(
            icon: Icons.add,
            enabled: canIncrease,
            onPressed: onIncrease,
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: AppColors.grayFill,
        shape: const CircleBorder(
          side: BorderSide(color: AppColors.grayStroke, width: 2),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            width: 63,
            height: 61,
            child: Icon(
              icon,
              size: 24,
              color: enabled ? AppColors.ink : AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}
