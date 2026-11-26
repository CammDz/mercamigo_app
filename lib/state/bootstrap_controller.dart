import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/utils/boot_log.dart';
import '../data/local/key_value_store.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';

/// Etapas del arranque de la aplicación.
enum BootstrapStage {
  /// Todavía no ha empezado.
  inicio('Iniciando la aplicación...'),

  /// Preparando el almacenamiento local del dispositivo.
  almacenamiento('Preparando el almacenamiento local...'),

  /// Conectando con el servidor (puede fallar: la app sigue en modo local).
  servidor('Conectando con el servidor...'),

  /// Restaurando la sesión guardada en el dispositivo.
  sesion('Restaurando la sesión...'),

  /// Todo listo.
  listo('Listo'),

  /// El arranque ha fallado.
  error('No se pudo iniciar la aplicación');

  const BootstrapStage(this.label);

  /// Texto visible para el usuario.
  final String label;
}

/// Orchestador del arranque.
///
/// La interfaz se dibuja **antes** de que estas operaciones terminen: el
/// usuario ve la pantalla de arranque (con la etapa actual) en lugar de una
/// pantalla negra. Ninguna etapa puede dejar la app esperando
/// indefinidamente: todas tienen tiempo límite.
class BootstrapController extends ChangeNotifier {
  BootstrapStage _stage = BootstrapStage.inicio;
  String? _errorMessage;
  String? _errorDetails;

  KeyValueStore? _store;
  SupabaseService? _supabase;
  AuthService? _auth;
  bool _running = false;

  /// Etapa actual del arranque.
  BootstrapStage get stage => _stage;

  /// Mensaje de error (si el arranque falló).
  String? get errorMessage => _errorMessage;

  /// Detalle técnico del error, para el registro.
  String? get errorDetails => _errorDetails;

  /// Almacenamiento local ya preparado.
  KeyValueStore? get store => _store;

  /// Servicio de Supabase (con `client == null` si se works en modo local).
  SupabaseService? get supabase => _supabase;

  /// Servicio de autenticación.
  AuthService? get auth => _auth;

  /// `true` cuando la app ya puede mostrar la pantalla principal.
  bool get isReady =>
      _stage == BootstrapStage.listo && _store != null && _auth != null;

  /// Ejecuta el arranque (o el reintento).
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _errorMessage = null;
    _errorDetails = null;
    _setStage(BootstrapStage.almacenamiento);

    try {
      final KeyValueStore store = await SharedPreferencesStore.create().timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'El almacenamiento local no respondió a tiempo',
          const Duration(seconds: 15),
        ),
      );
      _store = store;
      BootLog.stage('Almacenamiento local listo.');

      _setStage(BootstrapStage.servidor);
      // Si el servidor falla, `bootstrap` no lanza: la app sigue en modo local.
      final SupabaseService supabase = await SupabaseService.bootstrap(
        timeout: const Duration(seconds: 20),
      );
      _supabase = supabase;
      BootLog.stage(
        'Servidor: ${supabase.status.name}'
        '${supabase.errorMessage == null ? '' : ' (${supabase.errorMessage})'}',
      );

      _setStage(BootstrapStage.sesion);
      final AuthService auth = AuthService(supabase.client);
      await auth.restoreSession().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException(
          'No se pudo restaurar la sesión a tiempo',
          const Duration(seconds: 10),
        ),
      );
      _auth = auth;
      BootLog.stage('Sesión restaurada (${auth.status.name}).');

      _setStage(BootstrapStage.listo);
    } catch (error, stack) {
      BootLog.error('Fallo del arranque', error, stack);
      _errorMessage = 'No se pudo iniciar la aplicación.';
      _errorDetails = BootLog.redact('$error');
      _setStage(BootstrapStage.error);
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  /// Reintenta el arranque tras un error.
  Future<void> retry() => start();

  void _setStage(BootstrapStage stage) {
    _stage = stage;
    notifyListeners();
  }
}
