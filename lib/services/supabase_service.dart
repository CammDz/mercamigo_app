import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../core/utils/boot_log.dart';

/// Estado de la conexión con Supabase.
enum SupabaseStatus {
  /// La app se compiló sin `--dart-define`: funciona solo en modo local.
  disabled,

  /// Cliente inicializado correctamente.
  ready,

  /// No se pudo inicializar el cliente (URL o clave incorrectas, o el
  /// servidor no respondió a tiempo).
  error,
}

/// Arranque del cliente de Supabase.
///
/// La configuración llega por `--dart-define`; no hay credenciales en el
/// código. Si falta la configuración la app sigue funcionando **en modo
/// local** (catálogo y pedidos guardados en el dispositivo).
///
/// La inicialización tiene un **tiempo límite**: si el servidor no responde
/// (sin Internet, DNS lento, red bloqueada) no se queda esperando, sino que
/// cae en modo local para que la app arranque igualmente.
class SupabaseService {
  const SupabaseService({
    required this.client,
    required this.status,
    this.errorMessage,
  });

  final SupabaseClient? client;
  final SupabaseStatus status;
  final String? errorMessage;

  /// `true` cuando hay cliente disponible para hablar con el servidor.
  bool get isReady => client != null;

  /// Inicializa Supabase si la app fue compilada con la configuración.
  static Future<SupabaseService> bootstrap({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (!AppConfig.hasSupabase) {
      BootLog.stage('Sin configuración de Supabase: modo local.');
      return const SupabaseService(
        client: null,
        status: SupabaseStatus.disabled,
      );
    }

    BootLog.stage('Inicializando el cliente de Supabase...');
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabasePublishableKey,
      ).timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'Supabase no respondió en ${timeout.inSeconds} s',
          timeout,
        ),
      );
      BootLog.stage('Cliente de Supabase inicializado.');
      return SupabaseService(
        client: Supabase.instance.client,
        status: SupabaseStatus.ready,
      );
    } catch (error, stack) {
      BootLog.error('No se pudo inicializar Supabase', error, stack);
      return SupabaseService(
        client: null,
        status: SupabaseStatus.error,
        errorMessage:
            'No se pudo conectar con el servidor. La app funciona en modo local.',
      );
    }
  }
}
