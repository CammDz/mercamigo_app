import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../state/bootstrap_controller.dart';
import '../widgets/primary_button.dart';

/// Pantalla de arranque.
///
/// Se muestra mientras se prepara la app. Si algo falla, muestra el error y
/// un botón de reintento: nunca se queda en negro.
class BootstrapScreen extends StatelessWidget {
  const BootstrapScreen({
    super.key,
    required this.stage,
    required this.onRetry,
    this.errorMessage,
    this.errorDetails,
  });

  final BootstrapStage stage;
  final VoidCallback onRetry;
  final String? errorMessage;
  final String? errorDetails;

  @override
  Widget build(BuildContext context) {
    final bool failed = stage == BootstrapStage.error;
    final double width = MediaQuery.sizeOf(context).width;
    final bool wide = width >= 600;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 520 : 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: Image.asset(
                      'assets/figma/logo.png',
                      width: 120,
                      height: 108,
                      fit: BoxFit.contain,
                      errorBuilder:
                          (BuildContext context, Object error, StackTrace? stack) =>
                              const Icon(
                        Icons.shopping_basket_outlined,
                        size: 72,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    'Mercamigo',
                    textAlign: TextAlign.center,
                    style: AppText.display(wide ? 28 : 24, color: AppColors.ink),
                  ),
                  const SizedBox(height: 22),
                  if (failed) ...<Widget>[
                    const Icon(
                      Icons.error_outline,
                      size: 44,
                      color: AppColors.danger,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      errorMessage ?? 'No se pudo iniciar la aplicación.',
                      textAlign: TextAlign.center,
                      style: AppText.body(16, weight: FontWeight.w700),
                    ),
                    if (errorDetails != null) ...<Widget>[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF6F8FB),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          errorDetails!,
                          textAlign: TextAlign.center,
                          style: AppText.body(12.5, color: AppColors.muted),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    PrimaryButton(
                      label: 'Reintentar',
                      icon: Icons.refresh,
                      onPressed: onRetry,
                    ),
                  ] else ...<Widget>[
                    const Center(child: CircularProgressIndicator()),
                    const SizedBox(height: 22),
                    Text(
                      stage.label,
                      textAlign: TextAlign.center,
                      style: AppText.body(15, color: AppColors.muted),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
