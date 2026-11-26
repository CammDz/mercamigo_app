import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/validators.dart';
import '../../services/auth_service.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/primary_button.dart';

/// Creación de cuenta de comprador.
///
/// El registro público **siempre** crea una cuenta de comprador: no hay
/// forma de registrarse como administrador desde la app.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  static const String routeName = '/register';

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscure = true;
  bool _busy = false;
  String? _error;
  String? _pendingEmail;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String name = _nameController.text.trim();
    final String email = _emailController.text.trim();
    final String password = _passwordController.text;

    final String? nameError = Validators.nameError(name);
    if (nameError != null) {
      setState(() => _error = nameError);
      return;
    }
    final String? emailError = Validators.emailError(email);
    if (emailError != null) {
      setState(() => _error = emailError);
      return;
    }
    final String? passwordError = Validators.passwordError(password);
    if (passwordError != null) {
      setState(() => _error = passwordError);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final AuthService auth = context.read<AuthService>();
    final AuthOutcome outcome = await auth.signUp(
      name: name,
      email: email,
      password: password,
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = outcome.success ? null : outcome.message;
    });

    if (outcome.requiresEmailConfirmation) {
      setState(() => _pendingEmail = email);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pendingEmail != null) {
      return _ConfirmationPending(email: _pendingEmail!);
    }

    return AuthScaffold(
      title: 'Crear cuenta',
      subtitle: 'Registrate para comprar en Mercamigo.',
      footer: TextButton(
        onPressed: () => Navigator.of(context).maybePop(),
        child: Text(
          '¿Ya tienes cuenta? Iniciar sesión',
          style: AppText.body(
            15,
            weight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ),
      children: <Widget>[
        AuthField(
          controller: _nameController,
          label: 'Nombre',
          hint: 'Comprador',
          textCapitalization: TextCapitalization.words,
          autofocus: true,
        ),
        AuthField(
          controller: _emailController,
          label: 'Correo',
          hint: 'comprador@ejemplo.com',
          keyboardType: TextInputType.emailAddress,
        ),
        AuthField(
          controller: _passwordController,
          label: 'Contraseña',
          obscure: _obscure,
          onToggleObscure: () => setState(() => _obscure = !_obscure),
          onSubmitted: (String _) => _submit(),
        ),
        if (_error != null) ...<Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.danger.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              _error!,
              style: AppText.body(13, color: AppColors.danger),
            ),
          ),
          const SizedBox(height: 14),
        ],
        PrimaryButton(
          label: 'Crear cuenta',
          height: 46,
          isLoading: _busy,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}

/// Instrucciones cuando la cuenta quedó pendiente de confirmar el correo.
///
/// El usuario **no** se presenta como autenticado: la sesión solo existe
/// después de confirmar el correo desde el enlace.
class _ConfirmationPending extends StatelessWidget {
  const _ConfirmationPending({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Icon(
                    Icons.mark_email_read_outlined,
                    size: 64,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Confirma tu correo',
                    textAlign: TextAlign.center,
                    style: AppText.body(22, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Enviamos un enlace de confirmación a\n$email.',
                    textAlign: TextAlign.center,
                    style: AppText.body(15, color: AppColors.muted),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F9FE),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'Abre el enlace en este teléfono para confirmar la cuenta '
                      'y entrar. Hasta entonces no hay sesión iniciada.',
                      style: AppText.body(13.5, color: AppColors.muted),
                    ),
                  ),
                  const SizedBox(height: 22),
                  PrimaryButton(
                    label: 'Ir a iniciar sesión',
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
}
