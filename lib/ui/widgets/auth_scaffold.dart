import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Andamiaje común de las pantallas de autenticación.
///
/// Fondo blanco, logo, título centrado, subtítulo y una tarjeta lavanda con
/// borde azul que contiene los campos. El pie (enlaces de navegación) queda
/// al final de la pantalla cuando el contenido es más corto que el móvil.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.footer,
    this.belowCard,
    this.showCard = true,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? footer;

  /// Contenido opcional justo debajo de la tarjeta (avisos de Figma).
  final Widget? belowCard;

  /// `false` para pantallas cuyo contenido no va dentro de la tarjeta
  /// (por ejemplo, la verificación del código).
  final bool showCard;

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final bool wide = width >= 600;
    final double maxWidth = wide ? 480 : 420;
    const EdgeInsets padding = EdgeInsets.fromLTRB(24, 6, 24, 18);

    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: Image.asset(
            'assets/figma/logo.png',
            width: 110,
            height: 98,
            fit: BoxFit.contain,
            errorBuilder: (
              BuildContext context,
              Object error,
              StackTrace? stack,
            ) => const SizedBox(height: 82),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppText.display(wide ? 26 : 23, weight: FontWeight.w400),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: AppText.body(14, color: AppColors.textMuted, height: 1.3),
        ),
        const SizedBox(height: 20),
        if (showCard)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFF),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primary, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          )
        else
          ...children,
        if (belowCard != null) ...<Widget>[
          const SizedBox(height: 24),
          belowCard!,
        ],
      ],
    );

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return SingleChildScrollView(
              padding: padding,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: maxWidth,
                    minHeight:
                        constraints.maxHeight - padding.top - padding.bottom,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      content,
                      if (footer != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 26),
                          child: footer!,
                        ),
                    ],
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

/// Campo de texto con etiqueta encima, como en Figma.
class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.errorText,
    this.autofocus = false,
    this.maxLength,
    this.onSubmitted,
    this.onToggleObscure,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? errorText;
  final bool autofocus;
  final int? maxLength;
  final ValueChanged<String>? onSubmitted;

  /// Alterna la visibilidad del campo (para contraseñas).
  final VoidCallback? onToggleObscure;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: AppText.body(
              13,
              weight: FontWeight.w500,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 52,
            child: TextField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboardType,
              textCapitalization: textCapitalization,
              autofocus: autofocus,
              maxLength: maxLength,
              onSubmitted: onSubmitted,
              style: AppText.body(15, color: AppColors.ink),
              decoration: InputDecoration(
                hintText: hint,
                errorText: errorText,
                counterText: '',
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 13,
                ),
                hintStyle: AppText.body(15, color: AppColors.textMuted),
                suffixIcon: onToggleObscure == null
                    ? null
                    : IconButton(
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                          color: AppColors.textMuted,
                        ),
                        onPressed: onToggleObscure,
                        tooltip: obscure ? 'Mostrar' : 'Ocultar',
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF9A9A9A)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF9A9A9A)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
