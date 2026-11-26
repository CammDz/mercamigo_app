import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/order.dart';
import '../data/models/staff_order.dart';

/// Error de una operación de caja, con mensaje listo para mostrar.
class StaffException implements Exception {
  const StaffException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Página de pedidos de la caja.
class StaffOrderPage {
  const StaffOrderPage({required this.orders, required this.total});

  final List<StaffOrderSummary> orders;
  final int total;
}

/// Acceso a las funciones de caja del servidor.
///
/// **Toda** la autorización y todas las transiciones ocurren en la base de
/// datos: esta clase solo llama a las RPC y traduce sus respuestas. No hay
/// ninguna comprobación de permisos que dependa de la interfaz.
class StaffRepository {
  StaffRepository({required this.client});

  final SupabaseClient? client;

  bool get isConfigured => client != null;

  /// `true` si hay servidor y una sesión autenticada.
  bool get isAvailable => client != null && client!.auth.currentSession != null;

  /// Lista pedidos, opcionalmente filtrados por estado y búsqueda.
  Future<StaffOrderPage> listOrders({
    List<OrderStatus>? statuses,
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    final String search = (query ?? '').trim();
    final Map<String, dynamic> result = await _rpcJson(
      'listar_pedidos_personal',
      <String, dynamic>{
        'p_estados': statuses
            ?.map((OrderStatus status) => status.serverValue)
            .toList(growable: false),
        'p_busqueda': search.isEmpty ? null : search,
        'p_limite': limit,
        'p_offset': offset,
      },
    );

    final List<dynamic> raw =
        result['pedidos'] as List<dynamic>? ?? const <dynamic>[];
    return StaffOrderPage(
      orders: raw
          .whereType<Map<String, dynamic>>()
          .map(StaffOrderSummary.fromJson)
          .toList(growable: false),
      total: (result['total'] as num?)?.toInt() ?? 0,
    );
  }

  /// Detalle completo del recibo.
  Future<StaffOrderDetail> orderDetail(String orderId) async {
    final Map<String, dynamic> result = await _rpcJson(
      'detalle_pedido_personal',
      <String, dynamic>{'p_pedido_id': orderId},
    );
    return StaffOrderDetail.fromJson(result);
  }

  /// Busca por número de orden o por el código de barras que lo representa.
  Future<StaffOrderSearchResult> findByCode(String code) async {
    final Map<String, dynamic> result = await _rpcJson(
      'buscar_pedido_personal',
      <String, dynamic>{'p_codigo': code.trim()},
    );
    final bool found = result['encontrado'] == true;
    final Object? rawOrder = result['pedido'];
    return StaffOrderSearchResult(
      found: found,
      message: result['mensaje'] as String?,
      order: found && rawOrder is Map<String, dynamic>
          ? StaffOrderDetail.fromJson(rawOrder)
          : null,
    );
  }

  /// Registra el pago físico. No entrega el pedido.
  Future<StaffActionOutcome> confirmPayment(String orderId) async {
    final Map<String, dynamic> result = await _rpcJson(
      'confirmar_pago_pedido',
      <String, dynamic>{'p_pedido_id': orderId},
    );
    return StaffActionOutcome(
      status: OrderStatus.fromServer(result['estado'] as String?),
      message: result['mensaje'] as String? ?? 'Pago registrado.',
      registered: result['pago_registrado'] == true,
      alreadyDone: result['ya_estaba'] == true,
    );
  }

  /// Registra la entrega física. Solo el servidor decide si ya estaba pagada.
  Future<StaffActionOutcome> confirmDelivery(String orderId) async {
    final Map<String, dynamic> result = await _rpcJson(
      'confirmar_entrega_pedido',
      <String, dynamic>{'p_pedido_id': orderId},
    );
    return StaffActionOutcome(
      status: OrderStatus.fromServer(result['estado'] as String?),
      message: result['mensaje'] as String? ?? 'Entrega registrada.',
      registered: result['entrega_registrada'] == true,
      alreadyDone: result['ya_estaba'] == true,
    );
  }

  /// Reporte de ventas real entre dos fechas (hora de Bogotá).
  Future<SalesReport> salesReport({
    required DateTime from,
    required DateTime to,
  }) async {
    final DateFormat format = DateFormat('yyyy-MM-dd');
    final Map<String, dynamic> result = await _rpcJson(
      'reporte_ventas',
      <String, dynamic>{
        'p_desde': format.format(from),
        'p_hasta': format.format(to),
      },
    );
    return SalesReport.fromJson(result);
  }

  /// Personal con rol (solo administrador).
  Future<List<StaffMember>> listStaff() async {
    final Object? result = await _rpcRaw('listar_personal');
    final List<dynamic> rows = result is List<dynamic>
        ? result
        : const <dynamic>[];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(StaffMember.fromJson)
        .toList(growable: false);
  }

  /// Asigna o quita el rol de caja por correo (solo administrador).
  Future<StaffMember> setStaffByEmail({
    required String email,
    required bool assign,
  }) async {
    final Map<String, dynamic> result = await _rpcJson(
      'asignar_rol_personal_por_correo',
      <String, dynamic>{'p_correo': email.trim(), 'p_asignar': assign},
    );
    return StaffMember.fromJson(result);
  }

  Future<Map<String, dynamic>> _rpcJson(
    String name,
    Map<String, dynamic> params,
  ) async {
    final Object? result = await _rpcRaw(name, params: params);
    if (result is Map<String, dynamic>) return result;
    if (result is Map) return Map<String, dynamic>.from(result);
    return const <String, dynamic>{};
  }

  Future<Object?> _rpcRaw(String name, {Map<String, dynamic>? params}) async {
    final SupabaseClient? client = this.client;
    if (client == null) {
      throw const StaffException(
        'El servidor no está configurado en esta compilación.',
      );
    }
    if (client.auth.currentSession == null) {
      throw const StaffException('Tu sesión caducó. Vuelve a iniciar sesión.');
    }

    try {
      return await client.rpc(name, params: params);
    } on PostgrestException catch (error) {
      throw StaffException(_friendlyMessage(error));
    } on AuthException catch (error) {
      throw StaffException(
        'Tu sesión ya no es válida. Vuelve a iniciar sesión. '
        '(${error.message})',
      );
    } catch (error) {
      throw StaffException(
        'No se pudo completar la operación. Revisa tu conexión e inténtalo '
        'de nuevo. ($error)',
      );
    }
  }

  String _friendlyMessage(PostgrestException error) {
    final String message = error.message.trim();
    final String lower = message.toLowerCase();
    if (lower.contains('permisos de caja')) {
      return 'Tu cuenta no tiene permisos de caja.';
    }
    if (lower.contains('permisos de administrador')) {
      return 'Tu cuenta no tiene permisos de administrador.';
    }
    if (lower.contains('no existe')) {
      return message;
    }
    if (lower.contains('jwt') || lower.contains('session')) {
      return 'Tu sesión caducó. Vuelve a iniciar sesión.';
    }
    if (message.isEmpty) {
      return 'El servidor rechazó la operación.';
    }
    return message;
  }
}
