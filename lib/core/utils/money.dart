/// Formato de moneda colombiana (pesos).
///
/// Todos los importes se manejan como enteros en COP; aquí solo se aplica el
/// separador de miles para mostrarlo.
library;

/// Formatea [amount] (entero en pesos) como `$25,000`.
String formatCop(int amount) {
  final bool negative = amount < 0;
  final int value = amount.abs();
  final String digits = value.toString();
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${negative ? '-' : ''}\$$buffer';
}

/// Formatea un precio unitario sin decimales: `$2.800`.
String formatCopUnit(int amount) {
  final String formatted = formatCop(amount);
  return formatted.replaceAll(',', '.');
}
