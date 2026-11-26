import 'package:shared_preferences/shared_preferences.dart';

/// Almacenamiento clave/valor asíncrono.
///
/// Se abstrae para que los repositorios no dependan de `shared_preferences` y
/// las pruebas puedan usar una implementación en memoria.
abstract interface class KeyValueStore {
  Future<String?> readString(String key);

  Future<void> writeString(String key, String value);

  Future<void> remove(String key);
}

/// Implementación sobre `shared_preferences` (persistencia local en Android).
class SharedPreferencesStore implements KeyValueStore {
  SharedPreferencesStore(this._preferences);

  static Future<SharedPreferencesStore> create() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    return SharedPreferencesStore(preferences);
  }

  final SharedPreferences _preferences;

  @override
  Future<String?> readString(String key) async => _preferences.getString(key);

  @override
  Future<void> writeString(String key, String value) async {
    await _preferences.setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await _preferences.remove(key);
  }
}

/// Implementación en memoria, usada en pruebas.
class InMemoryStore implements KeyValueStore {
  InMemoryStore([Map<String, String>? initial])
    : _values = <String, String>{...?initial};

  final Map<String, String> _values;

  @override
  Future<String?> readString(String key) async => _values[key];

  @override
  Future<void> writeString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }
}
