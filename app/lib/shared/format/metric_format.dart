/// Formata um valor numérico de medida (kg, cm, %) sem `.0` decorativo —
/// mesma regra do `formatLoad` da execução de treino
/// (`features/workout/presentation/prescription_format.dart`), duplicada
/// aqui porque feature não importa feature (guideline flutter.md); unificar
/// os dois é limpeza futura, não bloqueia esta tarefa.
String formatMetric(double value) {
  final rounded = (value * 100).round() / 100;
  if (rounded == rounded.roundToDouble()) return rounded.toInt().toString();
  return rounded.toString();
}

/// Mesmo formato, com sinal explícito — para deltas ("+2.3", "-1").
String formatSignedMetric(double value) {
  final formatted = formatMetric(value.abs());
  if (value > 0) return '+$formatted';
  if (value < 0) return '-$formatted';
  return formatted;
}
