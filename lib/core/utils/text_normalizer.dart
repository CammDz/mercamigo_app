/// Utilidades de texto para la búsqueda global del catálogo.
///
/// La búsqueda debe ignorar mayúsculas y tildes ("jugo de naranja" tiene que
/// encontrar "Jugo de Naranja" y "Águila" tiene que encontrar "Aguila").
library;

const Map<String, String> _accentMap = <String, String>{
  'á': 'a',
  'à': 'a',
  'ä': 'a',
  'â': 'a',
  'ã': 'a',
  'å': 'a',
  'é': 'e',
  'è': 'e',
  'ë': 'e',
  'ê': 'e',
  'í': 'i',
  'ì': 'i',
  'ï': 'i',
  'î': 'i',
  'ó': 'o',
  'ò': 'o',
  'ö': 'o',
  'ô': 'o',
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'ü': 'u',
  'û': 'u',
  'ñ': 'n',
  'ç': 'c',
  'ý': 'y',
  'ÿ': 'y',
};

/// Normaliza una cadena: minúsculas, sin tildes y sin diacríticos.
///
/// Se usa tanto para el texto buscado como para el texto de cada producto,
/// de modo que la comparación sea insensible a mayúsculas y tildes.
String normalizeText(String input) {
  final StringBuffer buffer = StringBuffer();
  for (final int rune in input.toLowerCase().runes) {
    final String char = String.fromCharCode(rune);
    buffer.write(_accentMap[char] ?? char);
  }
  return buffer.toString().trim();
}

/// Indica si [haystack] contiene [needle] ignorando mayúsculas y tildes.
bool containsNormalized(String haystack, String needle) {
  final String normalizedNeedle = normalizeText(needle);
  if (normalizedNeedle.isEmpty) return true;
  return normalizeText(haystack).contains(normalizedNeedle);
}
