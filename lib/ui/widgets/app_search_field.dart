import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Campo de búsqueda del prototipo.
///
/// Fondo gris claro (#D9D9D9), esquinas de 10 px, lupa a la izquierda y texto
/// oscuro. Es el mismo campo en el catálogo y en el listado de productos.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    this.onChanged,
    this.hintText = 'Buscar Productos....',
    this.autofocus = false,
    this.onSubmitted,
    this.focusNode,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String hintText;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  /// Nodo de foco del campo.
  ///
  /// Permite quitar el foco al salir de la pantalla: si no, al volver a
  /// entrar el cursor aparece dentro de la barra de busqueda.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        style: AppText.body(16, color: AppColors.ink),
        decoration: InputDecoration(
          hintText: hintText,
          filled: true,
          fillColor: const Color(0xFFD9D9D9),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 11),
          hintStyle: AppText.body(16, color: const Color(0xFF4B4B4B)),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Image.asset(
              'assets/figma/icon_search.png',
              width: 27,
              height: 27,
              fit: BoxFit.contain,
              errorBuilder: (
                BuildContext context,
                Object error,
                StackTrace? stack,
              ) => const Icon(Icons.search, color: AppColors.ink, size: 24),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 47,
            minHeight: 27,
          ),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 20, color: AppColors.ink),
                  onPressed: () {
                    controller.clear();
                    onChanged?.call('');
                  },
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
          ),
        ),
      ),
    );
  }
}
