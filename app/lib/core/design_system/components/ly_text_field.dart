import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/ly_theme.dart';
import '../tokens/ly_spacing.dart';
import '../tokens/ly_typography.dart';

/// Campo de texto padrão, com rótulo acima e toggle de senha embutido.
class LyTextField extends StatefulWidget {
  const LyTextField({
    required this.label,
    super.key,
    this.hint,
    this.controller,
    this.obscure = false,
    this.keyboardType,
    this.prefixIcon,
    this.errorText,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.autofocus = false,
    this.minLines,
    this.maxLines,
    this.maxLength,
    this.inputFormatters,
    this.showPasswordLabel,
    this.hidePasswordLabel,
  }) : assert(
          !obscure || (showPasswordLabel != null && hidePasswordLabel != null),
          'obscure:true precisa de showPasswordLabel/hidePasswordLabel — '
          'o botão de mostrar/ocultar senha não pode ficar sem rótulo para '
          'leitor de tela (a11y, P4.3).',
        );

  final String label;
  final String? hint;
  final TextEditingController? controller;
  final bool obscure;
  final TextInputType? keyboardType;
  final IconData? prefixIcon;
  final String? errorText;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  /// Abre o campo já focado. Num diálogo com texto pré-preenchido é o que faz
  /// a seleção inicial valer: sem foco, digitar acrescenta ao valor de fábrica.
  final bool autofocus;

  /// Campo de várias linhas (observações): `minLines`/`maxLines` crescem o
  /// campo; `maxLength` limita o texto (o contador fica escondido).
  final int? minLines;
  final int? maxLines;
  final int? maxLength;

  /// Máscaras/filtros de entrada (ex.: campo de valor em reais).
  final List<TextInputFormatter>? inputFormatters;

  /// Rótulo do botão de alternar visibilidade quando a senha está oculta —
  /// obrigatório se `obscure: true` (o DS não conhece l10n, quem chama traz
  /// a string já traduzida).
  final String? showPasswordLabel;

  /// Mesmo rótulo, para quando a senha já está visível.
  final String? hidePasswordLabel;

  @override
  State<LyTextField> createState() => _LyTextFieldState();
}

class _LyTextFieldState extends State<LyTextField> {
  late bool _obscured = widget.obscure;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: LyType.label(c.textPrimary)),
        const SizedBox(height: LySpace.x2),
        TextField(
          controller: widget.controller,
          autofocus: widget.autofocus,
          obscureText: _obscured,
          minLines: widget.obscure ? 1 : widget.minLines,
          maxLines: widget.obscure ? 1 : widget.maxLines,
          maxLength: widget.maxLength,
          inputFormatters: widget.inputFormatters,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          onSubmitted: widget.onSubmitted,
          onChanged: widget.onChanged,
          style: LyType.body(c.textPrimary),
          decoration: InputDecoration(
            counterText: '',
            hintText: widget.hint,
            errorText: widget.errorText,
            prefixIcon: widget.prefixIcon == null
                ? null
                : Icon(widget.prefixIcon, size: 20, color: c.textSecondary),
            suffixIcon: widget.obscure
                ? IconButton(
                    onPressed: () => setState(() => _obscured = !_obscured),
                    tooltip: _obscured
                        ? widget.showPasswordLabel
                        : widget.hidePasswordLabel,
                    icon: Icon(
                      _obscured
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                      color: c.textSecondary,
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
