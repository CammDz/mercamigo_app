import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_service.dart';

/// Aviso sobre el modo de trabajo de la app.
///
/// · Con Supabase configurado y sesión iniciada: los pedidos se crean en el
///   servidor y el usuario puede consultar su historial.
/// · Sin servidor o sin sesión: los pedidos se guardan **solo en el
///   dispositivo** y no se pueden consultar desde otro equipo.
class ServerModeBanner extends StatelessWidget {
  const ServerModeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final SupabaseService supabase = context.read<SupabaseService>();
    final AuthService auth = context.watch<AuthService>();

    final String? message;
    final IconData icon;
    final Color color;

    if (supabase.status == SupabaseStatus.error) {
      message =
          supabase.errorMessage ??
          'No se pudo conectar con el servidor. La app trabaja en modo local.';
      icon = Icons.cloud_off_outlined;
      color = AppColors.danger;
    } else if (supabase.status == SupabaseStatus.disabled) {
      message = 'Modo local: los pedidos se guardan solo en este dispositivo.';
      icon = Icons.phonelink_off_outlined;
      color = AppColors.warning;
    } else if (!auth.isSignedIn) {
      message = 'Inicia sesión para guardar tus pedidos en la nube y ver tu historial.';
      icon = Icons.person_outline;
      color = AppColors.warning;
    } else {
      return const SizedBox.shrink();
    }

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
            child: Text(message, style: AppText.body(12.5, color: color)),
          ),
        ],
      ),
    );
  }
}
