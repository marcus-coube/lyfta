import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/l10n/gen/app_localizations.dart';

/// Barra de composição do chat: texto + anexar imagem + enviar.
///
/// Widget "burro": não sabe de presign nem de compressão, só reporta a
/// intenção (P3.5 §1) — quem decide o que fazer com o texto/a imagem é o
/// `ChatScreen`, via [onSendText]/[onPickImage].
class MessageInputBar extends StatefulWidget {
  const MessageInputBar({
    required this.onSendText,
    required this.onPickImage,
    super.key,
    this.sendingImage = false,
  });

  final ValueChanged<String> onSendText;
  final VoidCallback onPickImage;

  /// Desabilita o botão de imagem enquanto uma já está sendo processada
  /// (picker + compressão) — evita duas seleções simultâneas.
  final bool sendingImage;

  @override
  State<MessageInputBar> createState() => _MessageInputBarState();
}

class _MessageInputBarState extends State<MessageInputBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    widget.onSendText(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          LySpace.x3,
          LySpace.x2,
          LySpace.x3,
          LySpace.x2,
        ),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: widget.sendingImage ? null : widget.onPickImage,
              icon: const Icon(Icons.image_outlined),
              color: c.textSecondary,
              tooltip: l10n.chatAttachImage,
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
                style: LyType.body(c.textPrimary),
                decoration: InputDecoration(
                  hintText: l10n.chatMessageHint,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: LySpace.x2),
            IconButton(
              onPressed: _submit,
              icon: const Icon(Icons.send),
              color: c.accent,
              tooltip: l10n.chatSend,
            ),
          ],
        ),
      ),
    );
  }
}
