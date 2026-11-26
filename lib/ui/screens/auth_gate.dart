import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../services/auth_service.dart';
import '../../state/password_recovery_controller.dart';
import 'admin_panel_screen.dart';
import 'enter_recovery_code_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'staff_home_screen.dart';

/// Puerta de entrada según el estado de la sesión y el rol.
///
/// · Sin sesión: pantalla de inicio de sesión.
/// · Con sesión y rol de comprador: pantalla de inicio de compra.
/// · Con sesión y rol de administrador: **interfaz administrativa**, que no
///   es el inicio de compra con un botón añadido.
/// · Con sesión y rol de caja: interfaz de **personal de caja**.
/// · Con sesión y rol sin comprobar: estado de verificación.
///
/// Si llega un enlace de recuperación de contraseña, se abre la pantalla de
/// nueva contraseña.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _navigatingToRecovery = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkRecovery());
  }

  Future<void> _checkRecovery() async {
    final AuthService auth = context.read<AuthService>();
    if (!auth.recoveryRequired || _navigatingToRecovery) return;
    _navigatingToRecovery = true;

    // El enlace de recuperación abre la app: el cambio de contraseña sigue
    // exigiendo el código, así que se pide el código y se muestra su
    // pantalla. La sesión del enlace no basta para cambiar la contraseña.
    final String? email = auth.email;
    final PasswordRecoveryController recovery = context
        .read<PasswordRecoveryController>();
    if (email != null && email.isNotEmpty && !recovery.isFlowActive) {
      await recovery.requestCode(email);
      if (mounted) {
        await Navigator.of(context)
            .pushNamed(EnterRecoveryCodeScreen.routeName);
      }
    }

    if (!mounted) return;
    _navigatingToRecovery = false;
    auth.acknowledgeRecovery();
  }

  @override
  Widget build(BuildContext context) {
    final AuthService auth = context.watch<AuthService>();
    final PasswordRecoveryController recovery = context
        .watch<PasswordRecoveryController>();

    if (!auth.isSignedIn) {
      return const LoginScreen();
    }

    // El enlace de recuperacion puede llegar con la sesion ya abierta.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkRecovery());

    // Mientras se consulta el rol no se muestra ninguna pantalla de
    // "verificando": la app entra directamente en la experiencia de compra y,
    // si el servidor confirma el rol de administrador, cambia sola al panel.
    // Las acciones administrativas siguen comprobándose en el servidor.
    if (recovery.isFlowActive) {
      return const _RecoveryInProgress();
    }

    // Mientras el servidor confirma el rol no se muestra la pantalla de
    // comprador: si no, al entrar como administrador o caja se ve un parpadeo
    // del inicio de compra antes de cambiar de panel.
    final AdminRoleStatus role = auth.adminRoleStatus;
    if (role == AdminRoleStatus.unknown || role == AdminRoleStatus.checking) {
      return const _RoleLoading();
    }

    return homeForRole(role);
  }
}

/// Pantalla de inicio según el estado del rol.
///
/// Mientras el rol se consulta (o si la comprobación falla) se muestra la
/// experiencia de compra: no hay ninguna pantalla intermedia de "verificando
/// permisos". Si el servidor confirma el rol de administrador, se cambia al
/// panel administrativo; las acciones siguen comprobándose en el servidor.
@visibleForTesting
Widget homeForRole(AdminRoleStatus status) {
  if (status == AdminRoleStatus.admin) return const AdminPanelScreen();
  if (status == AdminRoleStatus.staff) return const StaffHomeScreen();
  return const HomeScreen();
}

/// Pantalla neutral mientras el servidor confirma el rol de la cuenta.
///
/// Evita el parpadeo del inicio de compra cuando la cuenta es de
/// administración o de caja.
class _RoleLoading extends StatelessWidget {
  const _RoleLoading();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Image.asset(
                'assets/figma/logo.png',
                width: 150,
                height: 130,
                fit: BoxFit.contain,
                errorBuilder:
                    (BuildContext context, Object error, StackTrace? stack) =>
                        const Icon(
                          Icons.shopping_basket_outlined,
                          size: 64,
                          color: AppColors.primary,
                        ),
              ),
              const SizedBox(height: 22),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pantalla neutral mientras se completa el cambio de contraseña.
///
/// No muestra ni la compra ni el panel de administración: el flujo de
/// recuperación es lo único que debe verse.
class _RecoveryInProgress extends StatelessWidget {
  const _RecoveryInProgress();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.lock_reset_outlined,
                  size: 56,
                  color: AppColors.primary,
                ),
                SizedBox(height: 16),
                Text(
                  'Cambiando la contraseña',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Termina el cambio de contraseña para continuar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
