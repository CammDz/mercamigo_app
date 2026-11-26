import 'dart:convert';

import '../core/utils/app_date_time.dart';
import '../data/local/key_value_store.dart';

/// Escaneo registrado del usuario.
///
/// Se guarda **solo en el dispositivo** y **separado por cuenta**: al
/// cambiar de usuario no se ven los escaneos del anterior.
class ScanHistoryEntry {
  const ScanHistoryEntry({
    required this.productId,
    required this.productName,
    required this.code,
    required this.scannedAt,
    this.imageUrl,
  });

  final String productId;
  final String productName;
  final String code;
  final DateTime scannedAt;
  final String? imageUrl;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'productoId': productId,
    'productoNombre': productName,
    'codigo': code,
    'escaneadoEn': toServerDate(scannedAt),
    'imagenUrl': imageUrl,
  };

  static ScanHistoryEntry fromJson(Map<String, dynamic> json) {
    return ScanHistoryEntry(
      productId: json['productoId'] as String? ?? '',
      productName: json['productoNombre'] as String? ?? '',
      code: json['codigo'] as String? ?? '',
      imageUrl: json['imagenUrl'] as String?,
      scannedAt:
          parseServerDate(json['escaneadoEn'] as String?) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// Historial de escaneos del usuario (local).
class ScanHistoryRepository {
  ScanHistoryRepository({required this.store});

  static const String _keyPrefix = 'mercamigo.scanhistory';
  static const int _maxEntries = 50;

  /// Tiempo durante el que un código repetido **no** genera una entrada
  /// nueva (la cámara detecta el mismo código en muchos fotogramas).
  static const Duration _dedupeWindow = Duration(minutes: 2);

  final KeyValueStore store;

  String _key(String userKey) => '$_keyPrefix.$userKey';

  /// Escaneos del usuario, del más reciente al más antiguo.
  Future<List<ScanHistoryEntry>> load(String userKey) async {
    final String? raw = await store.readString(_key(userKey));
    if (raw == null || raw.isEmpty) return const <ScanHistoryEntry>[];
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return const <ScanHistoryEntry>[];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ScanHistoryEntry.fromJson)
          .toList(growable: false);
    } on FormatException {
      return const <ScanHistoryEntry>[];
    }
  }

  /// Registra un escaneo correcto.
  ///
  /// No se guarda una entrada nueva por cada fotograma que detecta el mismo
  /// código: si el mismo código se repite dentro de [_dedupeWindow], se
  /// actualiza la fecha del escaneo anterior en lugar de duplicarlo.
  Future<void> add(String userKey, ScanHistoryEntry entry) async {
    final List<ScanHistoryEntry> entries = List<ScanHistoryEntry>.of(
      await load(userKey),
    );

    final int index = entries.indexWhere(
      (ScanHistoryEntry e) =>
          e.code == entry.code && e.productId == entry.productId,
    );
    if (index >= 0) {
      final ScanHistoryEntry previous = entries[index];
      if (secondsBetween(previous.scannedAt, DateTime.now()) < _dedupeWindow) {
        entries[index] = ScanHistoryEntry(
          productId: entry.productId,
          productName: entry.productName,
          code: entry.code,
          imageUrl: entry.imageUrl ?? previous.imageUrl,
          scannedAt: entry.scannedAt,
        );
        await _save(userKey, entries);
        return;
      }
    }

    entries.insert(0, entry);
    if (entries.length > _maxEntries) {
      entries.removeRange(_maxEntries, entries.length);
    }
    await _save(userKey, entries);
  }

  /// Borra el historial del usuario.
  Future<void> clear(String userKey) => store.remove(_key(userKey));

  Future<void> _save(String userKey, List<ScanHistoryEntry> entries) {
    return store.writeString(
      _key(userKey),
      jsonEncode(
        entries.map((ScanHistoryEntry e) => e.toJson()).toList(growable: false),
      ),
    );
  }
}
