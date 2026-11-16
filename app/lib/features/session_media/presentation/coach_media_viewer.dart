import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../domain/session_media.dart';

/// Dá ciência (e responde, se houver texto) e devolve a mídia atualizada.
typedef MediaAck = Future<SessionMedia> Function(String? feedback);

/// Constrói o player de vídeo; trocável no teste (plugin de plataforma).
typedef MediaPlayerBuilder = Widget Function(String url);

/// Data curta `DD/MM` no idioma do app.
String mediaDate(BuildContext context, DateTime date) =>
    DateFormat.Md(Localizations.localeOf(context).toString()).format(date);

/// Visualizador da mídia do aluno (ADR-020, P12.3 §2): vídeo ou imagem,
/// observação e exercício, com **Marcar como visto** e **Responder**. O aviso
/// de que a mídia será apagada em 7 dias fica visível antes de qualquer das
/// duas; depois da ciência, vira o selo "Apagada em DD/MM".
class CoachMediaViewer extends StatefulWidget {
  const CoachMediaViewer({
    super.key,
    required this.media,
    required this.onAck,
    this.playerBuilder,
  });

  final SessionMedia media;
  final MediaAck onAck;
  final MediaPlayerBuilder? playerBuilder;

  @override
  State<CoachMediaViewer> createState() => _CoachMediaViewerState();
}

class _CoachMediaViewerState extends State<CoachMediaViewer> {
  late SessionMedia _media = widget.media;
  final _reply = TextEditingController();
  bool _replying = false;
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _ack(String? feedback) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await widget.onAck(feedback);
      if (!mounted) return;
      setState(() {
        _media = updated.mediaUrl == null && _media.mediaUrl != null
            ? _media.withAck(updated)
            : updated;
        _replying = false;
        _reply.clear();
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final media = _media;
    final url = media.mediaUrl;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.coachMediaViewerTitle)),
      body: ListView(
        padding: const EdgeInsets.all(LySpace.x4),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: ClipRRect(
              borderRadius: LyRadius.md,
              child: ColoredBox(
                color: c.surface,
                child: url == null
                    ? const SizedBox(height: 160)
                    : media.isVideo
                        ? (widget.playerBuilder?.call(url) ??
                            _VideoBox(url: url))
                        : Image.network(
                            url,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const SizedBox(
                              height: 160,
                              child: Center(child: Icon(Icons.broken_image)),
                            ),
                          ),
              ),
            ),
          ),
          const SizedBox(height: LySpace.x3),
          Text(
            media.exerciseName ?? l10n.sessionMediaWholeWorkout,
            style: LyType.title(c.textPrimary),
          ),
          if (media.note != null) ...[
            const SizedBox(height: LySpace.x1),
            Text(
              l10n.coachMediaStudentNote(media.note!),
              key: const Key('viewer-note'),
              style: LyType.body(c.textSecondary),
            ),
          ],
          const SizedBox(height: LySpace.x4),
          if (media.isSeen)
            Row(
              key: const Key('viewer-deleted-on'),
              children: [
                Icon(Icons.check_circle, size: 16, color: c.success),
                const SizedBox(width: LySpace.x1),
                Expanded(
                  child: Text(
                    l10n.coachMediaDeletedOn(
                      mediaDate(context, media.deleteAfter),
                    ),
                    style: LyType.label(c.success),
                  ),
                ),
              ],
            )
          else ...[
            Text(
              l10n.coachMediaRetentionWarning,
              key: const Key('viewer-warning'),
              style: LyType.bodySm(c.warning),
            ),
            const SizedBox(height: LySpace.x3),
            LyButton(
              key: const Key('viewer-mark-seen'),
              label: l10n.coachMediaMarkSeen,
              variant: LyButtonVariant.secondary,
              onPressed: _busy ? null : () => unawaited(_ack(null)),
            ),
          ],
          const SizedBox(height: LySpace.x3),
          if (_replying) ...[
            TextField(
              key: const Key('viewer-reply-field'),
              controller: _reply,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(labelText: l10n.coachMediaReplyHint),
              onChanged: (_) => setState(() {}),
            ),
            LyButton(
              key: const Key('viewer-reply-send'),
              label: l10n.coachMediaReplySend,
              onPressed: _busy || _reply.text.trim().isEmpty
                  ? null
                  : () => unawaited(_ack(_reply.text)),
            ),
          ] else
            LyButton(
              key: const Key('viewer-reply'),
              label: l10n.coachMediaReply,
              onPressed: () => setState(() => _replying = true),
            ),
          if (_error != null) ...[
            const SizedBox(height: LySpace.x2),
            Text(
              describeApiError(context, _error!),
              key: const Key('viewer-error'),
              style: LyType.bodySm(c.danger),
            ),
          ],
        ],
      ),
    );
  }
}

/// Player de rede com play/pausa e barra de progresso.
class _VideoBox extends StatefulWidget {
  const _VideoBox({required this.url});

  final String url;

  @override
  State<_VideoBox> createState() => _VideoBoxState();
}

class _VideoBoxState extends State<_VideoBox> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await controller.initialize();
    } catch (_) {
      await controller.dispose();
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final controller = _controller;
    if (_failed) {
      return SizedBox(
        height: 160,
        child: Center(
          child: Text(
            AppLocalizations.of(context).coachMediaVideoFailed,
            style: LyType.bodySm(c.textSecondary),
          ),
        ),
      );
    }
    if (controller == null) {
      return const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: AspectRatio(
              aspectRatio: value.aspectRatio == 0 ? 16 / 9 : value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
          VideoProgressIndicator(controller, allowScrubbing: true),
          IconButton(
            key: const Key('viewer-play'),
            icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: () => value.isPlaying
                ? controller.pause()
                : controller.play(),
          ),
        ],
      ),
    );
  }
}
