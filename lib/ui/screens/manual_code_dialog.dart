import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../widgets/primary_button.dart';

/// Diálogo de ingreso manual del código.
///
/// Es la alternativa al escaneo con cámara cuando el permiso se denegó o la
/// cámara no está disponible.
Future<String?> showManualCodeDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) => const _ManualCodeDialog(),
  );
}

class _ManualCodeDialog extends StatefulWidget {
  const _ManualCodeDialog();

  @override
  State<_ManualCodeDialog> createState() => _ManualCodeDialogState();
}

class _ManualCodeDialogState extends State<_ManualCodeDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final String code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Ingresa un código.');
      return;
    }
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Ingresar código',
        style: AppText.body(19, weight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Escribe el código de barras del producto.',
            style: AppText.body(14, color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.text,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'Ej. 7701000000001',
              errorText: _error,
            ),
            onSubmitted: (String _) => _submit(),
          ),
          const SizedBox(height: 8),
          Text(
            'Los códigos se comparan ignorando mayúsculas y tildes.',
            style: AppText.body(12, color: AppColors.muted),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancelar', style: AppText.body(15)),
        ),
        SizedBox(
          width: 140,
          child: PrimaryButton(label: 'Buscar', height: 44, onPressed: _submit),
        ),
      ],
    );
  }
}
