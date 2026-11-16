import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../domain/session_media.dart';
import 'coach_media_controller.dart';
import 'coach_media_viewer.dart';

/// Abre o visualizador; a ciência passa pelo [CoachMediaController] do aluno,
/// que tira a mídia de "Para avaliar" e atualiza o card e o detalhe.
Future<void> openCoachMedia(
  BuildContext context,
  WidgetRef ref, {
  required String studentId,
  required SessionMedia media,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => CoachMediaViewer(
        media: media,
        onAck: (feedback) => ref
            .read(coachMediaProvider(studentId).notifier)
            .ack(media.id, feedback: feedback),
      ),
    ),
  );
}

/// "Para avaliar" (P12.3 §1): mídias sem ciência no topo da aba Check-ins,
/// independente de o aluno ter feito check-in. Some quando não há nada.
class CoachMediaToEvaluate extends ConsumerWidget {
  const CoachMediaToEvaluate({super.key, required this.studentId});

  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(coachMediaProvider(studentId));

    return state.when(
      loading: () => const SizedBox.shrink(),
      error: (error, _) => Row(
        key: const Key('media-to-evaluate-error'),
        children: [
          Expanded(
            child: Text(
              describeApiError(context, error),
              style: LyType.caption(c.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () =>
                unawaited(ref.read(coachMediaProvider(studentId).notifier).refresh()),
            child: Text(l10n.commonRetry),
          ),
        ],
      ),
      data: (data) {
        if (data.pending.isEmpty) return const SizedBox.shrink();
        return Column(
          key: const Key('media-to-evaluate'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.coachMediaToEvaluate,
              style: LyType.title(c.textPrimary),
            ),
            const SizedBox(height: LySpace.x2),
            for (final media in data.pending) ...[
              CoachMediaTile(studentId: studentId, media: media),
              const SizedBox(height: LySpace.x2),
            ],
            if (data.pendingHasMore)
              Align(
                child: LyButton(
                  key: const Key('media-to-evaluate-more'),
                  label: l10n.commonLoadMore,
                  variant: LyButtonVariant.secondary,
                  expanded: false,
                  onPressed: () => unawaited(
                    ref
                        .read(coachMediaProvider(studentId).notifier)
                        .loadMorePending(),
                  ),
                ),
              ),
            const SizedBox(height: LySpace.x4),
          ],
        );
      },
    );
  }
}

/// Mídias de uma sessão no card do check-in e no detalhe do treino (P12.3 §1).
class CoachSessionMedia extends ConsumerWidget {
  const CoachSessionMedia({
    super.key,
    required this.studentId,
    required this.sessionClientId,
  });

  final String studentId;
  final String sessionClientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref
            .watch(coachMediaProvider(studentId))
            .valueOrNull
            ?.forSession(sessionClientId) ??
        const <SessionMedia>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: LySpace.x3),
      child: Column(
        key: ValueKey('session-media-$sessionClientId'),
        children: [
          for (final media in items)
            Padding(
              padding: const EdgeInsets.only(bottom: LySpace.x2),
              child: CoachMediaTile(studentId: studentId, media: media),
            ),
        ],
      ),
    );
  }
}

/// Linha da mídia: miniatura, exercício e estado. Expirada = esmaecida, sem
/// player (P12.3 §3).
class CoachMediaTile extends ConsumerWidget {
  const CoachMediaTile({super.key, required this.studentId, required this.media});

  final String studentId;
  final SessionMedia media;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final title = media.exerciseName ?? l10n.sessionMediaWholeWorkout;

    if (media.isExpired) {
      return Opacity(
        opacity: 0.5,
        child: LyCard(
          key: ValueKey('coach-media-${media.id}'),
          padding: const EdgeInsets.all(LySpace.x3),
          child: Row(
            children: [
              Icon(Icons.hide_image_outlined, color: c.textSecondary),
              const SizedBox(width: LySpace.x3),
              Expanded(
                child: Text(
                  '${l10n.coachMediaExpired} · $title',
                  style: LyType.bodySm(c.textSecondary),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final status = media.isSeen
        ? l10n.coachMediaDeletedOn(mediaDate(context, media.deleteAfter))
        : l10n.coachMediaNew;
    return LyCard(
      key: ValueKey('coach-media-${media.id}'),
      padding: const EdgeInsets.all(LySpace.x3),
      onTap: () => unawaited(
        openCoachMedia(context, ref, studentId: studentId, media: media),
      ),
      child: Row(
        children: [
          Icon(
            media.isVideo ? Icons.play_circle_outline : Icons.image_outlined,
            color: media.isSeen ? c.textSecondary : c.accent,
          ),
          const SizedBox(width: LySpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: LyType.label(c.textPrimary)),
                Text(
                  status,
                  key: ValueKey('coach-media-status-${media.id}'),
                  style: LyType.caption(
                    media.isSeen ? c.success : c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
