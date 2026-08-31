import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/design_system/design_system.dart';
import '../../domain/exercise.dart';

/// Miniatura da mídia do exercício: GIF com cache de disco, vídeo com o
/// primeiro quadro em loop mudo.
///
/// Sem mídia (o caso dos globais hoje, ADR-010 §5), mostra o ícone do
/// equipamento em vez de um buraco no layout.
class ExerciseMedia extends StatelessWidget {
  const ExerciseMedia({
    required this.exercise,
    this.size = 56,
    this.borderRadius = LyRadius.md,
    super.key,
  });

  final Exercise exercise;
  final double size;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: size,
        height: size,
        child: switch (exercise.mediaType) {
          _ when !exercise.hasMedia => _Placeholder(color: c.textSecondary, bg: c.surfaceElevated),
          ExerciseMediaType.video => _VideoThumb(url: exercise.mediaUrl!),
          _ => CachedNetworkImage(
              imageUrl: exercise.mediaUrl!,
              fit: BoxFit.cover,
              placeholder: (context, _) => ColoredBox(color: c.surfaceElevated),
              errorWidget: (context, _, __) =>
                  _Placeholder(color: c.textSecondary, bg: c.surfaceElevated),
            ),
        },
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.color, required this.bg});

  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: bg,
      child: Icon(Icons.fitness_center, color: color, size: 20),
    );
  }
}

/// Vídeo curto do exercício, mudo e em loop — é demonstração de movimento,
/// não conteúdo com áudio.
class _VideoThumb extends StatefulWidget {
  const _VideoThumb({required this.url});

  final String url;

  @override
  State<_VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<_VideoThumb> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await controller.initialize();
      await controller.setVolume(0);
      await controller.setLooping(true);
      await controller.play();
    } catch (_) {
      // Mídia quebrada não pode derrubar a lista: cai no placeholder.
      await controller.dispose();
      if (mounted) setState(() => _controller = null);
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
    if (controller == null || !controller.value.isInitialized) {
      return ColoredBox(color: c.surfaceElevated);
    }
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}
