/// Zona horaria y formatos de fecha de Mercamigo.
///
/// La app muestra **todas** las fechas en `America/Bogota` (UTC-05:00), sin
/// importar la zona horaria del teléfono: la misma orden debe verse con la
/// misma hora en el celular del cliente, en el del cajero y en la imagen que
/// se comparte.
///
/// Reglas de la app:
///
/// * Dentro de la app siempre hay un **instante** (`DateTime`), nunca un
///   texto de fecha ni una cuenta regresiva calculada sobre texto.
/// * Para **mostrar** se usa [toBogota] (o los formateadores), que
///   devuelven la hora de pared de Bogotá. El resultado es solo para pintar:
///   nunca se vuelve a guardar ni a comparar.
/// * Para **guardar o enviar** se usa [toServerDate], que serializa siempre
///   en UTC (`...Z`). Así el instante se conserva intacto y no depende de la
///   zona del teléfono.
/// * Para **leer** del servidor se usa [parseServerDate], que interpreta bien
///   los `Z` y los desplazamientos horario, y que ancla a UTC-05:00 los
///   valores sin zona (la base de datos ya entrega la hora de Bogotá).
///
/// Colombia no aplica horario de verano desde 1992: el desplazamiento de
/// Bogotá es siempre de -05:00, por eso no hace falta la base de datos de
/// zonas horarias del sistema.
///
/// No se resta cinco horas "a mano" en dos sitios: la conversión ocurre una
/// sola vez, en el borde (al leer del servidor o al formatear para pintar).
library;

/// Zona horaria en la que se muestran las fechas de Mercamigo.
class AppTimeZone {
  const AppTimeZone._();

  /// Nombre IANA de la zona.
  static const String id = 'America/Bogota';

  /// Etiqueta legible del desplazamiento.
  static const String label = 'UTC-05:00';

  /// Desplazamiento de Bogotá respecto a UTC (sin horario de verano).
  static const Duration offset = Duration(hours: -5);
}

/// Expresión regular que detecta el desplazamiento horario al final de un
/// texto de fecha ISO 8601 (`Z`, `+00:00`, `-05:00`, `+0000`, `+00`).
///
/// Exige que antes haya una hora, para no confundir el signo de una fecha
/// sin hora (`2026-10-21`) con un desplazamiento.
final RegExp _zonePattern = RegExp(
  r'[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?\s*(Z|[+-]\d{2}:?\d{0,2})$',
  caseSensitive: false,
);

/// Convierte un instante a la hora de pared de Bogotá.
///
/// Devuelve un `DateTime` local cuyos campos (año, mes, día, hora, minuto...)
/// son los de Bogotá. Es el valor que se pinta en pantalla; no se debe
/// volver a guardar ni a comparar como si fuera un instante.
///
/// [instant] puede ser local o UTC: en ambos casos se interpreta como el
/// mismo punto de la línea de tiempo y se convierte una sola vez.
DateTime toBogota(DateTime instant) {
  final DateTime utc = instant.toUtc();
  final DateTime shifted = utc.add(AppTimeZone.offset);
  return DateTime(
    shifted.year,
    shifted.month,
    shifted.day,
    shifted.hour,
    shifted.minute,
    shifted.second,
    shifted.millisecond,
    shifted.microsecond,
  );
}

/// Formatea un instante como `dd/MM/yyyy HH:mm` en hora de Bogotá.
String formatBogotaDateTime(DateTime instant) {
  final DateTime bogota = toBogota(instant);
  return '${_two(bogota.day)}/${_two(bogota.month)}/${bogota.year} '
      '${_two(bogota.hour)}:${_two(bogota.minute)}';
}

/// Formatea un instante como `dd/MM/yyyy` en hora de Bogotá.
String formatBogotaDate(DateTime instant) {
  final DateTime bogota = toBogota(instant);
  return '${_two(bogota.day)}/${_two(bogota.month)}/${bogota.year}';
}

/// Formatea un instante como `dd/MM HH:mm` en hora de Bogotá.
String formatBogotaShortDateTime(DateTime instant) {
  final DateTime bogota = toBogota(instant);
  return '${_two(bogota.day)}/${_two(bogota.month)} '
      '${_two(bogota.hour)}:${_two(bogota.minute)}';
}

/// Lee una **fecha de calendario** (`YYYY-MM-DD`) sin convertirla de zona.
///
/// Se usa para los periodos de los reportes: `2026-11-25` significa el día
/// 25 en Bogotá, no un instante que pueda caer en otro día al convertirlo.
DateTime? parseCalendarDate(String? raw) {
  if (raw == null) return null;
  final DateTime? parsed = DateTime.tryParse(raw.trim());
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// Formatea una fecha de calendario como `dd/MM/yyyy`, sin cambiar de zona.
String formatCalendarDate(DateTime date) =>
    '${_two(date.day)}/${_two(date.month)}/${date.year}';

/// Lee la fecha que devuelve el servidor y la deja como instante.
///
/// * Con `Z` o con desplazamiento (`-05:00`, `+00:00`...) el instante es
///   exactamente el que indica el texto, sin tocarlo.
/// * Sin zona (la base de datos ya entrega la hora de Bogotá) el texto se
///   ancla a UTC-05:00, de modo que no dependa de la zona del teléfono.
///
/// Devuelve `null` si el texto está vacío o no se puede interpretar.
DateTime? parseServerDate(String? raw) {
  if (raw == null) return null;
  final String value = raw.trim();
  if (value.isEmpty) return null;

  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed == null) return null;

  if (_zonePattern.hasMatch(value)) {
    // El texto ya dice en qué instante es: se respeta tal cual.
    return parsed.toUtc();
  }

  // Sin zona: son los campos de la hora de Bogotá. El instante es ese
  // momento en UTC, es decir, los campos mas el desplazamiento.
  return DateTime.utc(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
    parsed.millisecond,
    parsed.microsecond,
  ).subtract(AppTimeZone.offset);
}

/// Serializa un instante para guardarlo o enviarlo al servidor.
///
/// Siempre en UTC (`...Z`): conserva el instante original y no depende de la
/// zona horaria del teléfono ni de la del servidor.
String toServerDate(DateTime instant) => instant.toUtc().toIso8601String();

/// Cuenta los segundos que faltan entre dos instantes.
///
/// Se comparan instantes (UTC), nunca dos textos de fecha ya formateados.
Duration secondsBetween(DateTime from, DateTime to) =>
    to.toUtc().difference(from.toUtc());

/// Hora de Bogotá en formato de 12 horas (`10:30 a. m.`).
String formatBogotaClock(DateTime instant) {
  final DateTime bogota = toBogota(instant);
  final int hour = bogota.hour % 12 == 0 ? 12 : bogota.hour % 12;
  final String suffix = bogota.hour < 12 ? 'a. m.' : 'p. m.';
  return '$hour:${_two(bogota.minute)} $suffix';
}

/// Texto relativo corto para las listas de caja (`Hace 3 min`).
///
/// Pasada la primera hora se muestra el día y la hora de Bogotá
/// (`Hoy · 10:30 a. m.`, `Ayer · 4:15 p. m.` o `25/11 · 9:05 a. m.`).
String formatRelativeTime(DateTime instant, {DateTime? now}) {
  final DateTime reference = (now ?? DateTime.now()).toUtc();
  final Duration difference = reference.difference(instant.toUtc());
  if (difference.inSeconds < 60) return 'Hace un momento';
  if (difference.inMinutes < 60) return 'Hace ${difference.inMinutes} min';

  final DateTime date = toBogota(instant);
  final DateTime today = toBogota(reference);
  final DateTime day = DateTime(today.year, today.month, today.day);
  final DateTime target = DateTime(date.year, date.month, date.day);
  final int days = day.difference(target).inDays;
  if (days == 0) return 'Hoy · ${formatBogotaClock(instant)}';
  if (days == 1) return 'Ayer · ${formatBogotaClock(instant)}';
  return '${_two(date.day)}/${_two(date.month)} · ${formatBogotaClock(instant)}';
}

String _two(int value) => value.toString().padLeft(2, '0');
