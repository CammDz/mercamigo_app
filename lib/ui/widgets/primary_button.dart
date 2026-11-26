import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Botón principal de la app: azul, redondeado y con la tipografía del
/// prototipo (League Spartan).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.backgroundColor = AppColors.primary,
    this.foregroundColor = Colors.white,
    this.height = 52,
    this.isLoading = false,
    this.outlined = false,
  });

  /// Botón secundario (contorno gris en lugar de relleno azul).
  const PrimaryButton.outlined({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.backgroundColor = Colors.white,
    this.foregroundColor = AppColors.ink,
    this.height = 52,
    this.isLoading = false,
    this.outlined = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final double height;
  final bool isLoading;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final Widget content = isLoading
        ? SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 22, color: foregroundColor),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: AppText.body(
                    17,
                    weight: FontWeight.w700,
                    color: foregroundColor,
                  ),
                ),
              ),
            ],
          );

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(height / 2),
        elevation: 0,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(height / 2),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(height / 2),
              border: outlined
                  ? Border.all(color: AppColors.grayBorderDark, width: 1.4)
                  : null,
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: content,
          ),
        ),
      ),
    );
  }
}
