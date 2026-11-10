import 'package:flutter/material.dart';

import '../../core/design_system/design_system.dart';
import '../money/money.dart';

/// Campo de valor em reais com máscara: o que se digita vira centavos
/// inteiros (`1.234,56` em pt, `1,234.56` em en → `123456`). O campo expõe só
/// `int` — nunca `double`. Vazio = `null`.
class LyMoneyField extends StatefulWidget {
  const LyMoneyField({
    required this.label,
    required this.cents,
    required this.onChanged,
    super.key,
    this.errorText,
    this.fieldKey,
  });

  final String label;

  /// Valor atual em centavos; mudar de fora (ex.: escolher outro plano)
  /// reescreve o texto.
  final int? cents;
  final ValueChanged<int?> onChanged;
  final String? errorText;

  /// Chave do `TextField` interno, para os testes digitarem nele.
  final Key? fieldKey;

  @override
  State<LyMoneyField> createState() => _LyMoneyFieldState();
}

class _LyMoneyFieldState extends State<LyMoneyField> {
  final _controller = TextEditingController();
  String? _locale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context).toString();
    if (_locale != locale) {
      _locale = locale;
      _sync();
    }
  }

  @override
  void didUpdateWidget(LyMoneyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cents != parseCents(_controller.text)) _sync();
  }

  void _sync() {
    final cents = widget.cents;
    _controller.text = cents == null ? '' : maskCents(cents, _locale!);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LyTextField(
      key: widget.fieldKey,
      label: widget.label,
      controller: _controller,
      keyboardType: TextInputType.number,
      errorText: widget.errorText,
      inputFormatters: [MoneyInputFormatter(_locale!)],
      onChanged: (text) => widget.onChanged(parseCents(text)),
    );
  }
}
