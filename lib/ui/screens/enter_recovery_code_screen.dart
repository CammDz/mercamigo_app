import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../state/password_recovery_controller.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/primary_button.dart';
import 'reset_password_screen.dart';

/// Introducir el código de recuperación recibido por correo.
///
/// El código se verifica con `verifyOTP` (tipo `recovery`) dentro de la app:
/// no se acepta pasar a la nueva contraseña sin esa verificación.
class EnterRecoveryCodeScreen extends StatefulWidget {
  const EnterRecoveryCodeScreen({super.key, this.showEmail = true});

  static const String routeName = '/recovery-code';

  /// Si es `false` no se muestra el correo (pantalla de "Mi cuenta").
  final bool showEmail;

  @override
  State<EnterRecoveryCodeScreen> createState() =>
      _EnterRecoveryCodeScreenState();
}

class _EnterRecoveryCodeScreenState extends State<EnterRecoveryCodeScreen> {
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocus = FocusNode();

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  /// Normaliza lo que se pega: se quitan espacios y separadores.
  String _normalize(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

  void _onChanged(String value) {
    final String digits = _normalize(value);
    if (digits != value) {
      _codeController.value = TextEditingValue(
        text: digits,
        selection: TextSelection.collapsed(offset: digits.length),
      );
    }
  }

  Future<void> _submit() async {
    final PasswordRecoveryController recovery = context
        .read<PasswordRecoveryController>();
    final String code = _codeController.text.trim();
    if (code.length != PasswordRecoveryController.codeLength) {
      return;
    }
    final bool ok = await recovery.verifyCode(code);
    if (!mounted) return;
    if (ok) {
      await Navigator.of(context).pushNamed(ResetPasswordScreen.routeName);
    }
  }

  Future<void> _resend() async {
    final PasswordRecoveryController recovery = context
        .read<PasswordRecoveryController>();
    final String? email = recovery.email;
    if (email == null) return;
    await recovery.requestCode(email, isResend: true);
  }

  @override
  Widget build(BuildContext context) {
    final PasswordRecoveryController recovery = context
        .watch<PasswordRecoveryController>();
    final bool verifying =
        recovery.stage == PasswordRecoveryStage.verifyingCode;
    final String code = _codeController.text.trim();
    final bool complete = code.length == PasswordRecoveryController.codeLength;

    return PopScope(
      // Si el usuario cancela, el flujo se limpia (no queda a medias).
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) context.read<PasswordRecoveryController>().cancel();
      },
      child: AuthScaffold(
        showCard: false,
        title: 'Código de recuperación',
        subtitle: 'Escribe el código que te enviamos al correo.',
        footer: TextButton(
          onPressed: verifying
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
          if (widget.showEmail && recovery.email != null) ...<Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF1FC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Enviado a ${recovery.maskedEmail}',
                style: AppText.body(14, weight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (widget.showEmail && recovery.email != null) ...<Widget>[
            Text(
              'Código de ${PasswordRecoveryController.codeLength} dígitos',
              style: AppText.body(13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 6),
          ],
          SizedBox(
            height: 52,
            child: TextField(
              controller: _codeController,
              focusNode: _codeFocus,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: PasswordRecoveryController.codeLength,
              inputFormatters: const <TextInputFormatter>[
                _OtpDigitsFormatter(),
              ],
              style: AppText.body(
                24,
                weight: FontWeight.w700,
                color: AppColors.ink,
                letterSpacing: 8,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                counterText: '',
                hintText: '01234567',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 1.5,
                  ),
                ),
              ),
              onChanged: (String value) {
                _onChanged(value);
                setState(() {});
              },
              onSubmitted: (String _) => _submit(),
            ),
          ),
          if (recovery.error != null) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                recovery.error!,
                style: AppText.body(13, color: AppColors.danger),
              ),
            ),
          ],
          const SizedBox(height: 18),
          PrimaryButton(
            label: 'Verificar código',
            height: 56,
            isLoading: verifying,
            // No se verifica hasta completar la longitud del código.
            onPressed: !complete || verifying ? null : _submit,
          ),
          const SizedBox(height: 10),
          PrimaryButton.outlined(
            label: recovery.canResend
                ? 'Reenviar código'
                : 'Reenviar en ${recovery.resendSecondsLeft} s',
            height: 56,
            onPressed: recovery.canResend ? _resend : null,
          ),
        ],
      ),
    );
  }
}

/// Formateador del campo del codigo: solo deja digitos y no deja escribir
/// mas de los que pide el servidor.
///
/// Filtra **antes** de recortar, para que pegar un codigo con espacios o
/// guiones no pierda digitos: "0123 4567" se convierte en "01234567".
class _OtpDigitsFormatter extends TextInputFormatter {
  const _OtpDigitsFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final String limited = digits.length > PasswordRecoveryController.codeLength
        ? digits.substring(0, PasswordRecoveryController.codeLength)
        : digits;
    if (limited == newValue.text) return newValue;
    return TextEditingValue(
      text: limited,
      selection: TextSelection.collapsed(offset: limited.length),
    );
  }
}
