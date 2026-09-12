import 'package:intl/intl.dart';

/// Formata um valor numérico de medida (kg, cm, %) sem `.0` decorativo, com
/// separador decimal/milhar do `locale` (ADR-011 §4 — nunca `toString()` cru,
/// que sempre usa `.` independente do idioma) — mesma regra do `formatLoad`
/// da execução de treino
/// (`features/workout/presentation/prescription_format.dart`), duplicada
/// aqui porque feature não importa feature (guideline flutter.md); unificar
/// os dois é limpeza futura, não bloqueia esta tarefa.
String formatMetric(double value, String locale) {
  return NumberFormat('#,##0.##', locale).format(value);
}

/// Mesmo formato, com sinal explícito — para deltas ("+2,3", "-1").
String formatSignedMetric(double value, String locale) {
  final formatted = formatMetric(value.abs(), locale);
  if (value > 0) return '+$formatted';
  if (value < 0) return '-$formatted';
  return formatted;
}
