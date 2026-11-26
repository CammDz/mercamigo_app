import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../services/auth_service.dart';
import '../../state/password_recovery_controller.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/primary_button.dart';

/// Establecer una nueva contraseña.
///
/// Solo se puede usar después de que el código de recuperación se haya
/// verificado **en este mismo intento** (`verifyOTP` con tipo `recovery`).
/// No se acepta como prueba un valor guardado ni un parámetro de la ruta:
/// la comprobación vive en [PasswordRecoveryController] y solo se activa
/// tras una verificación correcta.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  static const String routeName = '/reset-password';

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _busy = false;
  bool _done = false;
  bool _showPassword = false;
  String? _error;

  /// Error al cerrar la sesión **después** de cambiar la contraseña.
  ///
  /// La contraseña ya está cambiada: solo queda cerrar la sesión, y eso se
  /// puede reintentar sin repetir el cambio.
  String? _signOutError;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// Cierra la sesión tras un cambio correcto.
  Future<void> _closeSession() async {
    final SignOutResult result = await context.read<AuthService>().signOut();
    if (!mounted) return;
    if (!result.sessionClosed) {
      setState(() {
        _signOutError =
            'Tu contraseña sí se cambió, pero no se pudo cerrar la sesión. '
            'Puedes reintentar el cierre.';
      });
      return;
    }
    context.read<PasswordRecoveryController>().cancel();
  }

  Future<void> _submit() async {
    final PasswordRecoveryController recovery = context
        .read<PasswordRecoveryController>();
    if (!recovery.isCodeVerified) {
      setState(() => _error = 'Verifica primero el código de recuperación.');
      return;
    }

    final String password = _passwordController.text;
    final String confirm = _confirmController.text;

    if (password.length < 6) {
      setState(
        () => _error = 'La contraseña debe tener al menos 6 caracteres.',
      );
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final bool ok = await recovery.setNewPassword(password, confirm);

    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = ok ? null : recovery.error;
      _done = ok;
    });

    if (ok) {
      // La contraseña ya está cambiada: se cierra la sesión para volver a
      // entrar con la nueva contraseña.
      await _closeSession();
    }
  }

  void _finish() {
    // Se vuelve al inicio de sesión (primera ruta del Navigator).
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final PasswordRecoveryController recovery = context
        .watch<PasswordRecoveryController>();

    if (_done) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      Icons.check_circle_outline,
                      size: 64,
                      color: AppColors.success,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Contraseña actualizada',
                      textAlign: TextAlign.center,
                      style: AppText.body(21, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ya puedes entrar con tu nueva contraseña.',
                      textAlign: TextAlign.center,
                      style: AppText.body(14, color: AppColors.muted),
                    ),
                    if (_signOutError != null) ...<Widget>[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _signOutError!,
                          textAlign: TextAlign.center,
                          style: AppText.body(13, color: AppColors.warning),
                        ),
                      ),
                      const SizedBox(height: 10),
                      PrimaryButton.outlined(
                        label: 'Reintentar el cierre de sesión',
                        icon: Icons.refresh,
                        isLoading: _busy,
                        onPressed: _busy
                            ? null
                            : () async {
                                setState(() => _busy = true);
                                await _closeSession();
                                if (mounted) setState(() => _busy = false);
                              },
                      ),
                    ],
                    const SizedBox(height: 22),
                    PrimaryButton(
                      label: 'Ir a iniciar sesión',
                      onPressed: _finish,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Sin verificación previa no se deja cambiar la contraseña.
    if (!recovery.isCodeVerified) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      Icons.lock_outline,
                      size: 60,
                      color: AppColors.warning,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Verifica primero el código',
                      textAlign: TextAlign.center,
                      style: AppText.body(20, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Para cambiar la contraseña hay que verificar el código '
                      'que te enviamos al correo.',
                      textAlign: TextAlign.center,
                      style: AppText.body(14, color: AppColors.muted),
                    ),
                    const SizedBox(height: 22),
                    PrimaryButton(
                      label: 'Volver',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return AuthScaffold(
      title: 'Nueva contraseña',
      subtitle: 'Escribe la contraseña que vas a usar para entrar.',
      footer: TextButton(
        onPressed: _busy
            ? null
            : () {
                context.read<PasswordRecoveryController>().cancel();
                Navigator.of(context).maybePop();
              },
        child: Text(
          'Cancelar',
          style: AppText.body(
            15,
            weight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ),
      children: <Widget>[
        AuthField(
          controller: _passwordController,
          label: 'Nueva contraseña',
          obscure: !_showPassword,
          autofocus: true,
          onToggleObscure: () => setState(() => _showPassword = !_showPassword),
        ),
        AuthField(
          controller: _confirmController,
          label: 'Confirmar contraseña',
          obscure: !_showPassword,
          onSubmitted: (String _) => _submit(),
        ),
        if (_error != null) ...<Widget>[
          Text(_error!, style: AppText.body(13, color: AppColors.danger)),
          const SizedBox(height: 14),
        ],
        PrimaryButton(
          label: 'Guardar contraseña',
          height: 46,

          isLoading: _busy,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}
