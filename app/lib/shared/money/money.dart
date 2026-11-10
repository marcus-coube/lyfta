import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Dinheiro em centavos inteiros (ADR-007): nenhuma conta nem leitura de valor
/// passa por `double`. A única conversão para número fracionário é a da
/// exibição ([formatCents]), onde o teto de [maxCents] (R$ 10 milhões) está
/// muito abaixo dos 2^53 em que o `double` deixaria de ser exato.
const int maxCents = 1000000000;

/// Valor formatado como moeda no [locale] da tela ("R$ 1.234,56").
String formatCents(int cents, String locale, {String currency = 'BRL'}) {
  return NumberFormat.simpleCurrency(
    locale: locale,
    name: currency,
    decimalDigits: 2,
  ).format(cents / 100);
}

/// Texto do campo (sem símbolo da moeda): "1.234,56" em pt-BR, "1,234.56" em
/// en. Montado com inteiros, sem `double`.
String maskCents(int cents, String locale) {
  final grouping = NumberFormat.decimalPattern(locale);
  final decimalSep = grouping.symbols.DECIMAL_SEP;
  final units = grouping.format(cents ~/ 100);
  final fraction = (cents % 100).toString().padLeft(2, '0');
  return '$units$decimalSep$fraction';
}

/// Lê os centavos do texto digitado: só os dígitos contam, os dois últimos são
/// os centavos (a máscara de moeda: digitar `123456` vira `1.234,56`).
/// Vazio devolve `null`; acima de [maxCents] também.
int? parseCents(String text) {
  final digits = text.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  if (digits.length > 12) return null;
  final cents = int.parse(digits);
  return cents > maxCents ? null : cents;
}

/// Máscara de moeda do campo de valor: a cada tecla reformata o texto a partir
/// dos dígitos. Colar "1.234,56" ou "1,234.56" dá o mesmo valor, nos dois
/// idiomas.
class MoneyInputFormatter extends TextInputFormatter {
  MoneyInputFormatter(this.locale);

  final String locale;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final cents = parseCents(digits);
    // Passou do teto: ignora a tecla.
    if (cents == null) return oldValue;
    final text = maskCents(cents, locale);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
