import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/staff_order.dart';
import '../../repositories/staff_repository.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/primary_button.dart';

/// Gestión del **personal de caja** desde la administración.
///
/// El administrador asigna o quita el rol por correo. El servidor comprueba
/// que quien llama es administrador y **rechaza la autoasignación**: nadie
/// puede darse permisos de caja a sí mismo desde la app.
class AdminStaffScreen extends StatefulWidget {
  const AdminStaffScreen({super.key});

  static const String routeName = '/admin/personal';

  @override
  State<AdminStaffScreen> createState() => _AdminStaffScreenState();
}

class _AdminStaffScreenState extends State<AdminStaffScreen> {
  final TextEditingController _emailController = TextEditingController();

  List<StaffMember> _members = const <StaffMember>[];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<StaffMember> members =
          await context.read<StaffRepository>().listStaff();
      if (!mounted) return;
      setState(() {
        _members = members;
        _loading = false;
      });
    } on StaffException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el personal: $error';
        _loading = false;
      });
    }
  }

  Future<void> _assign({required bool assign}) async {
    if (_busy) return;
    final String email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _snack('Escribe el correo de una cuenta existente.', isError: true);
      return;
    }

    setState(() => _busy = true);
    try {
      final StaffMember member = await context
          .read<StaffRepository>()
          .setStaffByEmail(email: email, assign: assign);
      if (!mounted) return;
      _emailController.clear();
      _snack(
        assign
            ? '${member.name.isEmpty ? member.email : member.name} ahora '
                'tiene rol de caja.'
            : 'Se quitó el rol de caja a ${member.email}.',
      );
      await _load();
    } on StaffException catch (error) {
      if (!mounted) return;
      _snack(error.message, isError: true);
    } catch (error) {
      if (!mounted) return;
      _snack('No se pudo cambiar el rol: $error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.danger : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppTopBar(
        title: 'Personal de caja',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
            children: <Widget>[
              Text(
                'Asigna el rol de caja por correo. La cuenta debe existir y '
                'no puede ser la tuya: el servidor rechaza la autoasignación.',
                style: AppText.body(13, color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Correo de la cuenta',
                  hintText: 'cajero@ejemplo.com',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
              ),
              const SizedBox(height: 10),
              PrimaryButton(
                label: 'Asignar rol de caja',
                icon: Icons.person_add_alt_1_outlined,
                isLoading: _busy,
                onPressed: _busy ? null : () => _assign(assign: true),
              ),
              const SizedBox(height: 8),
              PrimaryButton.outlined(
                label: 'Quitar rol de caja',
                icon: Icons.person_remove_outlined,
                onPressed: _busy ? null : () => _assign(assign: false),
              ),
              const SizedBox(height: 20),
              Text(
                'Cuentas con rol',
                style: AppText.body(16, weight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 26),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Column(
                  children: <Widget>[
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: AppText.body(13.5, color: AppColors.danger),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Reintentar'),
                    ),
                  ],
                )
              else if (_members.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Todavía no hay cuentas con rol asignado.',
                    style: AppText.body(13, color: AppColors.muted),
                  ),
                )
              else
                for (final StaffMember member in _members)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          member.isAdmin
                              ? Icons.admin_panel_settings_outlined
                              : Icons.point_of_sale_outlined,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                member.name.isEmpty
                                    ? member.email
                                    : member.name,
                                style: AppText.body(
                                  14,
                                  weight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                member.email,
                                style: AppText.body(
                                  12,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          member.isAdmin ? 'Administrador' : 'Caja',
                          style: AppText.body(
                            11.5,
                            weight: FontWeight.w700,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
