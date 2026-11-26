import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Código de barras de un producto, dibujado **en el dispositivo**.
///
/// Usa Code 128 con el código registrado del producto, así que no depende de
/// una Edge Function ni de Internet. El texto que se ve es el mismo que se
/// escanea.
class ProductBarcode extends StatelessWidget {
  const ProductBarcode({
    super.key,
    required this.code,
    this.height = 92,
    this.showCodeText = true,
  });

  /// Código registrado del producto.
  final String code;

  /// Alto de las barras.
  final double height;

  /// Muestra el código en texto debajo de las barras.
  final bool showCodeText;

  @override
  Widget build(BuildContext context) {
    final String value = code.trim();
    if (value.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.surfaceSoft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.view_week_outlined,
              size: 26,
              color: AppColors.muted,
            ),
            const SizedBox(height: 8),
            Text(
              'Código no disponible',
              style: AppText.body(14, color: AppColors.muted),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.grayBorder, width: 1.1),
          ),
          child: BarcodeWidget(
            barcode: Barcode.code128(),
            data: value,
            height: height,
            drawText: false,
            color: Colors.black,
            backgroundColor: Colors.white,
            errorBuilder: (BuildContext context, String error) {
              return SizedBox(
                height: height,
                child: Center(
                  child: Text(
                    'No se pudo dibujar el código.',
                    textAlign: TextAlign.center,
                    style: AppText.body(13, color: AppColors.danger),
                  ),
                ),
              );
            },
          ),
        ),
        if (showCodeText) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            value,
            textAlign: TextAlign.center,
            style: AppText.body(
              13.5,
              weight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ],
    );
  }
}
