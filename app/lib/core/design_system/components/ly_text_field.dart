import 'package:flutter/material.dart';

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
  });

  final String label;
  final String? hint;
  final TextEditingController? controller;
  final bool obscure;
  final TextInputType? keyboardType;
  final IconData? prefixIcon;
  final String? errorText;
  final TextInputAction? textInputAction;

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
          obscureText: _obscured,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          style: LyType.body(c.textPrimary),
          decoration: InputDecoration(
            hintText: widget.hint,
            errorText: widget.errorText,
            prefixIcon: widget.prefixIcon == null
                ? null
                : Icon(widget.prefixIcon, size: 20, color: c.textSecondary),
            suffixIcon: widget.obscure
                ? IconButton(
                    onPressed: () => setState(() => _obscured = !_obscured),
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
