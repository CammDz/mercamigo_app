import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/app_date_time.dart';
import '../../data/models/user_profile.dart';
import '../../repositories/order_repository.dart';
import '../../repositories/profile_repository.dart';
import '../../services/auth_service.dart';
import '../../state/cart_controller.dart';
import '../../state/order_controller.dart';
import '../../state/order_history_controller.dart';
import '../../state/password_recovery_controller.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/primary_button.dart';
import 'admin_panel_screen.dart';
import 'enter_recovery_code_screen.dart';
import 'my_orders_screen.dart';

/// "Mi cuenta": datos del usuario, acceso al historial y cierre de sesión.
class MyAccountScreen extends StatefulWidget {
  const MyAccountScreen({super.key});

  static const String routeName = '/account';

  @override
  State<MyAccountScreen> createState() => _MyAccountScreenState();
}

class _MyAccountScreenState extends State<MyAccountScreen> {
  final TextEditingController _nameController = TextEditingController();

  UserProfile? _profile;
  bool _loadingProfile = true;
  bool _saving = false;
  bool _sendingCode = false;
  bool _signingOut = false;
  String? _signOutError;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final AuthService auth = context.read<AuthService>();
    final String? userId = auth.userId;
    if (userId == null) {
      if (mounted) setState(() => _loadingProfile = false);
      return;
    }
    final ProfileRepository repository = context.read<ProfileRepository>();
    final UserProfile? profile = await repository.loadProfile(userId);
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _loadingProfile = false;
      if (!_prefilled && profile != null) {
        _prefilled = true;
        _nameController.text = profile.name;
      }
    });
  }

  /// Pide el código de recuperación para el correo de la cuenta.
  ///
  /// La sesión activa **no** sirve para cambiar la contraseña: también hay
  /// que verificar el código que llega al correo. El correo no se puede
  /// cambiar en este recorrido: se usa el de la cuenta autenticada.
  Future<void> _changePassword() async {
    final String? email = context.read<AuthService>().email;
    if (email == null || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo leer el correo de la cuenta.'),
        ),
      );
      return;
    }

    setState(() => _sendingCode = true);
    final PasswordRecoveryController recovery = context
        .read<PasswordRecoveryController>();
    final bool ok = await recovery.requestCode(email);
    if (!mounted) return;
    setState(() => _sendingCode = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            recovery.error ??
                'No se pudo enviar el código. Inténtalo de nuevo.',
          ),
        ),
      );
      return;
    }

    await Navigator.of(context).pushNamed(EnterRecoveryCodeScreen.routeName);
  }

  Future<void> _saveName() async {
    final AuthService auth = context.read<AuthService>();
    final String? userId = auth.userId;
    if (userId == null) return;
    setState(() => _saving = true);
    final bool ok = await context.read<ProfileRepository>().updateName(
      userId,
      _nameController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Nombre actualizado.' : 'No se pudo actualizar el nombre.',
        ),
      ),
    );
    if (ok) await _loadProfile();
  }

  /// Cierra la sesión.
  ///
  /// 1. Cierra la sesión real de Supabase (local y, si se puede, remota).
  /// 2. Limpia el estado privado del usuario anterior (carrito, copia local
  ///    de pedidos e historial en memoria).
  /// 3. Lleva al inicio de sesión eliminando las rutas protegidas del
  ///    historial de navegación ("Atrás" no debe volver a ellas).
  ///
  /// Si el cierre falla se informa y se puede reintentar.
  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() {
      _signingOut = true;
      _signOutError = null;
    });

    final AuthService auth = context.read<AuthService>();
    // Los controladores se guardan antes de navegar: despues el contexto de
    // esta pantalla ya no existe.
    final CartController cart = context.read<CartController>();
    final OrderRepository orders = context
        .read<OrderController>()
        .orderRepository;
    final OrderHistoryController history = context
        .read<OrderHistoryController>();
    // El aviso global (el de la app) sobrevive a la navegacion.
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(
      Navigator.of(context, rootNavigator: true).context,
    );

    // 1) Cierre de sesion local **inmediato**: se manda al login sin esperar
    //    a que el servidor revoque el token.
    final Future<SignOutResult> closing = auth.signOut();

    // 2) Al login, quitando las rutas protegidas del historial.
    if (mounted) {
      Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
    }

    // 3) La limpieza de datos y el aviso de errores siguen en segundo plano.
    SignOutResult result;
    try {
      result = await closing;
    } catch (error) {
      result = SignOutResult(sessionClosed: false, remoteError: '$error');
    }

    // El estado privado se limpia siempre: no se dejan datos de la cuenta
    // anterior en el dispositivo aunque el cierre haya fallado.
    await _clearPrivateState(cart, orders, history);

    if (!result.sessionClosed) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo cerrar la sesion. Revisa tu conexion e intentalo de '
            'nuevo.',
          ),
        ),
      );
      return;
    }

    if (result.remoteError != null) {
      // La sesion local esta cerrada; solo fallo la revocacion en el
      // servidor. Se informa sin bloquear el cierre.
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Sesion cerrada en este dispositivo. No se pudo revocar en el '
            'servidor; el token caduca igualmente.',
          ),
        ),
      );
    }
  }

  /// Borra los datos privados de la cuenta anterior.
  Future<void> _clearPrivateState(
    CartController cart,
    OrderRepository orders,
    OrderHistoryController history,
  ) async {
    try {
      await cart.clear();
    } catch (_) {
      // El carrito puede estar vacio o no guardarse: no impide cerrar sesion.
    }
    try {
      await orders.clearLocal();
    } catch (_) {}
    try {
      history.clear();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final AuthService auth = context.watch<AuthService>();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppTopBar(
        title: 'Mi cuenta',
        titleStyle: AppText.display(25, weight: FontWeight.w700),
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double maxWidth = constraints.maxWidth >= 600 ? 620 : 460;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Tus datos',
                              style: AppText.body(17, weight: FontWeight.w700),
                            ),
                            const SizedBox(height: 12),
                            if (_loadingProfile)
                              const Center(child: CircularProgressIndicator())
                            else ...<Widget>[
                              TextField(
                                controller: _nameController,
                                textCapitalization: TextCapitalization.words,
                                decoration: const InputDecoration(
                                  labelText: 'Nombre',
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Correo: ${auth.email ?? '-'}',
                                style: AppText.body(14, color: AppColors.muted),
                              ),
                              if (_profile != null) ...<Widget>[
                                const SizedBox(height: 4),
                                Text(
                                  'Miembro desde ${_formatDate(_profile!.createdAt)}',
                                  style: AppText.body(
                                    12.5,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                              if (auth.isAdmin) ...<Widget>[
                                const SizedBox(height: 10),
                                const _AdminBadge(),
                              ],
                              const SizedBox(height: 14),
                              PrimaryButton(
                                label: 'Guardar nombre',
                                icon: Icons.save_outlined,
                                isLoading: _saving,
                                onPressed: _saving ? null : _saveName,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _Card(
                        child: Column(
                          children: <Widget>[
                            // El historial de pedidos es del comprador: el
                            // administrador trabaja con productos, tienda y
                            // códigos, no con sus propios pedidos.
                            if (!auth.isAdmin) ...<Widget>[
                              _MenuRow(
                                title: 'Mis pedidos',
                                subtitle: 'Historial de tus compras',
                                onTap: () =>
                                    Navigator.of(context)
                                        .pushNamed(MyOrdersScreen.routeName),
                              ),
                              const Divider(height: 22),
                            ],
                            _MenuRow(
                              title: 'Cambiar contraseña',
                              subtitle: 'Te enviamos un código al correo',
                              onTap: _sendingCode ? null : _changePassword,
                            ),
                            if (auth.isAdmin) ...<Widget>[
                              const Divider(height: 22),
                              _MenuRow(
                                title: 'Panel administrador',
                                subtitle: 'Productos, códigos y configuración de tienda',
                                onTap: () =>
                                    Navigator.of(context)
                                        .pushNamed(AdminPanelScreen.routeName),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (_signOutError != null) ...<Widget>[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _signOutError!,
                            textAlign: TextAlign.center,
                            style: AppText.body(13, color: AppColors.danger),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      PrimaryButton.outlined(
                        label: 'Cerrar sesión',
                        icon: Icons.logout,
                        foregroundColor: AppColors.danger,
                        isLoading: _signingOut,
                        onPressed: _signingOut ? null : _signOut,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Al cerrar sesión se borran del dispositivo el carrito y '
                        'la copia local de los pedidos. Tu historial queda '
                        'asociado a tu cuenta.',
                        textAlign: TextAlign.center,
                        style: AppText.body(12, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Tarjeta blanca del estilo del prototipo.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: child,
    );
  }
}

/// Fila de menú dentro de una tarjeta.
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: AppText.body(15, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppText.body(12.5, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// Distintivo de administrador.
class _AdminBadge extends StatelessWidget {
  const _AdminBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.shield_outlined, size: 15, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            'Administrador',
            style: AppText.body(
              12.5,
              weight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Formatea una fecha de alta del perfil (siempre en hora de Bogota).
String _formatDate(DateTime date) => formatBogotaDate(date);
