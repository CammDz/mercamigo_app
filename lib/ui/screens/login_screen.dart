import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../services/auth_service.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/primary_button.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

/// Inicio de sesión con correo y contraseña.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  static const String routeName = '/login';

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String email = _emailController.text.trim();
    final String password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Escribe tu correo y tu contraseña.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final AuthService auth = context.read<AuthService>();
    final AuthOutcome outcome = await auth.signIn(
      email: email,
      password: password,
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = outcome.success ? null : outcome.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AuthService auth = context.watch<AuthService>();

    return AuthScaffold(
      title: 'Iniciar sesión',
      subtitle: 'Entra con tu correo y contraseña para ver tus pedidos.',
      footer: Column(
        children: <Widget>[
          TextButton(
            onPressed: () =>
                Navigator.of(context).pushNamed(RegisterScreen.routeName),
            child: Text(
              '¿No tienes cuenta? Crear cuenta',
              style: AppText.body(
                15,
                weight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pushNamed(ForgotPasswordScreen.routeName),
            child: Text(
              '¿Olvidaste tu contraseña?',
              style: AppText.body(
                15,
                weight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
          if (!auth.isConfigured)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'El servidor no está configurado en esta compilación: '
                'los pedidos se guardarán solo en este dispositivo.',
                textAlign: TextAlign.center,
                style: AppText.body(12, color: AppColors.muted),
              ),
            ),
        ],
      ),
      children: <Widget>[
        AuthField(
          controller: _emailController,
          label: 'Correo',
          hint: 'comprador@ejemplo.com',
          keyboardType: TextInputType.emailAddress,
          textCapitalization: TextCapitalization.none,
          autofocus: true,
          onSubmitted: (String _) => _submit(),
        ),
        AuthField(
          controller: _passwordController,
          label: 'Contraseña',
          obscure: _obscure,
          onToggleObscure: () => setState(() => _obscure = !_obscure),
          onSubmitted: (String _) => _submit(),
        ),
        if (_error != null) ...<Widget>[
          _ErrorBox(message: _error!),
          const SizedBox(height: 14),
        ],
        PrimaryButton(
          label: 'Iniciar sesión',
          height: 46,
          isLoading: _busy || auth.isBusy,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}

/// Mensaje de error dentro de la tarjeta.
class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.error_outline, size: 18, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppText.body(13, color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}
