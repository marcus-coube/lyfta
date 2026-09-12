import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/l10n/gen/app_localizations.dart';

/// Uma bolha do chat — texto ou imagem, própria ou do outro participante.
///
/// Widget "burro" (só dados + callbacks, P2.4 §convenção): não conhece
/// `ChatMessage`/`PendingMessage`, só o que precisa desenhar. É o que faz o
/// teste de widget do Aceite (P3.5) montar casos sem subir controller nem
/// repositório.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    required this.isMine,
    required this.timestamp,
    super.key,
    this.body = '',
    this.imageBytes,
    this.imageUrl,
    this.read = false,
    this.sending = false,
    this.failed = false,
    this.onRetry,
    this.onDiscard,
  });

  final bool isMine;
  final String body;
  final Uint8List? imageBytes;
  final String? imageUrl;
  final DateTime timestamp;

  /// Só relevante quando [isMine] — o outro participante já leu.
  final bool read;

  /// Envio otimista em voo (P3.5 §1) — mostra um indicador discreto em vez
  /// da hora.
  final bool sending;

  /// Envio que falhou de vez — chat não tem fila offline (ADR-003 §1), então
  /// a única saída é a pessoa decidir tentar de novo ou descartar.
  final bool failed;
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;

  bool get _hasImage => imageBytes != null || (imageUrl ?? '').isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    final bubbleColor = isMine ? c.accent : c.surfaceElevated;
    final textColor = isMine ? c.onAccent : c.textPrimary;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Opacity(
          opacity: failed ? 0.6 : 1,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: LySpace.x1),
            padding: const EdgeInsets.all(LySpace.x3),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: LyRadius.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_hasImage) ...[
                  ClipRRect(
                    borderRadius: LyRadius.md,
                    child: SizedBox(
                      width: 220,
                      height: 220,
                      child: imageBytes != null
                          ? Image.memory(imageBytes!, fit: BoxFit.cover)
                          : CachedNetworkImage(
                              imageUrl: imageUrl!,
                              fit: BoxFit.cover,
                              placeholder: (context, _) =>
                                  ColoredBox(color: c.surfaceElevated),
                              errorWidget: (context, _, __) => ColoredBox(
                                color: c.surfaceElevated,
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: c.textSecondary,
                                ),
                              ),
                            ),
                    ),
                  ),
                  if (body.isNotEmpty) const SizedBox(height: LySpace.x2),
                ],
                if (body.isNotEmpty)
                  Text(body, style: LyType.body(textColor)),
                const SizedBox(height: LySpace.x1),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _timeLabel(),
                      style: LyType.caption(
                        isMine ? c.onAccent.withValues(alpha: 0.75) : c.textSecondary,
                      ),
                    ),
                    if (isMine && !sending && !failed) ...[
                      const SizedBox(width: LySpace.x1),
                      Icon(
                        read ? Icons.done_all : Icons.done,
                        size: 14,
                        color: read
                            ? c.info
                            : c.onAccent.withValues(alpha: 0.75),
                      ),
                    ],
                  ],
                ),
                if (failed) ...[
                  const SizedBox(height: LySpace.x2),
                  // `Wrap`, não `Row`: bolha estreita + "não enviada" +
                  // "tentar de novo" + "remover" junto não cabe numa linha
                  // só sem estourar a largura da bolha.
                  Wrap(
                    spacing: LySpace.x2,
                    runSpacing: LySpace.x1,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        l10n.chatMessageFailed,
                        style: LyType.caption(c.danger),
                      ),
                      GestureDetector(
                        onTap: onRetry,
                        child: Text(
                          l10n.chatMessageRetry,
                          style: LyType.caption(c.info),
                        ),
                      ),
                      if (onDiscard != null)
                        GestureDetector(
                          onTap: onDiscard,
                          child: Text(
                            l10n.commonRemove,
                            style: LyType.caption(c.textSecondary),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _timeLabel() {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
