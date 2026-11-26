import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../state/password_recovery_controller.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/primary_button.dart';
import 'enter_recovery_code_screen.dart';

/// Solicitud del código de recuperación de contraseña.
///
/// Se pide el código con `resetPasswordForEmail`. La respuesta es **genérica**
/// ("Si el correo está registrado, recibirás un código para continuar"): así
/// no se revela si una cuenta existe.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  static const String routeName = '/forgot-password';

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _emailController = TextEditingController();

  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Escribe el correo de tu cuenta.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final PasswordRecoveryController recovery = context
        .read<PasswordRecoveryController>();
    final bool ok = await recovery.requestCode(email);

    if (!mounted) return;
    setState(() {
      _busy = false;
      _sent = ok;
      _error = ok ? null : recovery.error;
    });
  }

  Future<void> _continue() async {
    await Navigator.of(context).pushNamed(EnterRecoveryCodeScreen.routeName);
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Recuperar contraseña',
      subtitle: 'Te enviamos un código para crear una contraseña nueva.',
      footer: TextButton(
        onPressed: _busy
            ? null
            : () {
                context.read<PasswordRecoveryController>().cancel();
                Navigator.of(context).maybePop();
              },
        child: Text(
          'Volver a iniciar sesión',
          style: AppText.body(
            15,
            weight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ),
      belowCard: _sent
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(
                        Icons.check_circle_outline,
                        size: 20,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Si el correo está registrado, recibirás un código '
                          'para continuar.',
                          style: AppText.body(
                            14,
                            weight: FontWeight.w600,
                            color: AppColors.success,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  label: 'Escribir el código',
                  onPressed: _continue,
                ),
              ],
            )
          : null,
      children: <Widget>[
        AuthField(
          controller: _emailController,
          label: 'Correo',
          hint: 'comprador@ejemplo.com',
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          onSubmitted: (String _) => _submit(),
        ),
        if (_error != null) ...<Widget>[
          Text(_error!, style: AppText.body(13, color: AppColors.danger)),
          const SizedBox(height: 14),
        ],
        PrimaryButton(
          label: _sent ? 'Reenviar código' : 'Enviar código',
          height: 56,
          isLoading: _busy,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}
