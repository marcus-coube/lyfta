import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/ly_error_state.dart';
import '../../../shared/widgets/ly_skeleton.dart';
import '../../session_media/presentation/coach_media_controller.dart';
import '../../session_media/presentation/coach_media_widgets.dart';
import '../../workout/domain/session_metrics.dart';
import '../../workout/presentation/prescription_format.dart';
import '../domain/checkin.dart';
import '../domain/coach_session.dart';
import 'checkin_answers.dart';
import 'checkins_controller.dart';
import 'coach_sessions_controller.dart';

/// Aba de check-ins na ficha do aluno, vista pelo coach (P3.5 §3) — a fila
/// já ordenada pelo servidor (não revisados primeiro, P3.3), com o badge de
/// pendentes no rótulo da aba (o `Tab` do `EvolutionScreen` embrulha isto).
class CoachCheckinsTab extends ConsumerWidget {
  const CoachCheckinsTab({required this.studentId, super.key});

  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final checkins = ref.watch(checkinsProvider(studentId));

    return checkins.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(LySpace.x4),
        child: Column(
          children: [
            LySkeletonListTile(),
            SizedBox(height: LySpace.x4),
            LySkeletonListTile(),
            SizedBox(height: LySpace.x4),
            LySkeletonListTile(),
          ],
        ),
      ),
      error: (error, _) => LyErrorState(
        message: describeApiError(context, error),
        retryable: isRetryableError(error),
        onRetry: () => ref.read(checkinsProvider(studentId).notifier).refresh(),
      ),
      data: (state) {
        final empty = state.items.isEmpty;
        // Posição 0 é a seção "Para avaliar" (some sozinha sem mídia).
        final count = 1 + (empty ? 1 : state.items.length + (state.hasMore ? 1 : 0));
        return RefreshIndicator(
          onRefresh: () async {
            unawaited(ref.read(coachMediaProvider(studentId).notifier).refresh());
            await ref.read(checkinsProvider(studentId).notifier).refresh();
          },
          child: ListView.separated(
            // Sempre rolável: o puxar para atualizar vale também sem itens.
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              LySpace.x4,
              LySpace.x4,
              LySpace.x4,
              LySpace.x16,
            ),
            itemCount: count,
            separatorBuilder: (_, index) =>
                SizedBox(height: index == 0 ? 0 : LySpace.x3),
            itemBuilder: (context, index) {
              if (index == 0) return CoachMediaToEvaluate(studentId: studentId);
              final i = index - 1;
              if (empty) {
                return Padding(
                  padding: const EdgeInsets.only(top: LySpace.x8),
                  child: Center(
                    child: Text(
                      l10n.checkinListEmpty,
                      style: LyType.body(c.textSecondary),
                    ),
                  ),
                );
              }
              // Página seguinte (P8.3): a fila passa de 30 itens.
              if (i == state.items.length) {
                return Align(
                  child: LyButton(
                    key: const Key('checkins_load_more'),
                    label: l10n.commonLoadMore,
                    variant: LyButtonVariant.secondary,
                    expanded: false,
                    onPressed: () => unawaited(
                      ref.read(checkinsProvider(studentId).notifier).loadMore(),
                    ),
                  ),
                );
              }
              return _CheckinCard(
                studentId: studentId,
                checkin: state.items[i],
                onReview: () => ref
                    .read(checkinsProvider(studentId).notifier)
                    .review(state.items[i].id),
              );
            },
          ),
        );
      },
    );
  }
}

class _CheckinCard extends ConsumerWidget {
  const _CheckinCard({
    required this.studentId,
    required this.checkin,
    required this.onReview,
  });

  final String studentId;
  final WorkoutCheckin checkin;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final sessions = ref.watch(coachSessionsProvider(studentId));

    return LyCard(
      padding: const EdgeInsets.all(LySpace.x4),
      onTap: () => context.push(
        '/students/$studentId/sessions/${checkin.sessionClientId}',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckinAnswers(checkin: checkin),
          const SizedBox(height: LySpace.x3),
          _SessionLine(
            session: sessions.found[checkin.sessionClientId],
            failed: sessions.failed.contains(checkin.sessionClientId),
            looked: sessions.looked.contains(checkin.sessionClientId),
            onRetry: () => unawaited(
              ref.read(coachSessionsProvider(studentId).notifier).retry(),
            ),
          ),
          CoachSessionMedia(
            studentId: studentId,
            sessionClientId: checkin.sessionClientId,
          ),
          const SizedBox(height: LySpace.x3),
          if (checkin.isReviewed)
            Row(
              children: [
                Icon(Icons.check_circle, size: 16, color: c.success),
                const SizedBox(width: LySpace.x1),
                Text(l10n.checkinReviewed, style: LyType.caption(c.success)),
              ],
            )
          else
            LyButton(
              label: l10n.checkinMarkReviewed,
              variant: LyButtonVariant.secondary,
              expanded: false,
              onPressed: onReview,
            ),
        ],
      ),
    );
  }
}

/// Linha do treino no card (P11.2 §1): rótulo do dia + plano e as métricas.
/// Sem sessão no servidor ainda: aviso neutro; lookup falho: sem a linha e
/// com retry. Enquanto o lookup não voltou, nada (a lista não espera por ele).
class _SessionLine extends StatelessWidget {
  const _SessionLine({
    required this.session,
    required this.failed,
    required this.looked,
    required this.onRetry,
  });

  final CoachSession? session;
  final bool failed;
  final bool looked;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final s = session;

    if (s != null) {
      return Column(
        key: const Key('checkin_session_line'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sessionTitleWithPlan(l10n, s),
            style: LyType.label(c.textPrimary),
          ),
          const SizedBox(height: LySpace.x1),
          Text(
            sessionMetricsLine(l10n, s),
            style: LyType.caption(c.textSecondary),
          ),
        ],
      );
    }
    if (failed) {
      return Row(
        key: const Key('checkin_session_failed'),
        children: [
          Expanded(
            child: Text(
              l10n.checkinSessionLookupFailed,
              style: LyType.caption(c.textSecondary),
            ),
          ),
          TextButton(
            key: const Key('checkin_session_retry'),
            onPressed: onRetry,
            child: Text(l10n.commonRetry),
          ),
        ],
      );
    }
    if (looked) {
      return Text(
        l10n.checkinSessionNotSynced,
        key: const Key('checkin_session_not_synced'),
        style: LyType.caption(c.textSecondary),
      );
    }
    return const SizedBox.shrink();
  }
}

/// `Treino A · Plano de força`.
String sessionTitleWithPlan(AppLocalizations l10n, CoachSession s) {
  final title = l10n.sessionTitle(s.dayLabel);
  return s.planTitle.isEmpty ? title : '$title · ${s.planTitle}';
}

/// `12 séries · 96 reps · 4.200 kg · 0:52:10` (duração só se confiável).
String sessionMetricsLine(AppLocalizations l10n, CoachSession s) {
  return [
    l10n.checkinSessionSets(s.setsCount),
    l10n.checkinSessionReps(s.repsTotal),
    l10n.checkinSessionVolume(formatLoad(s.volumeKg, l10n.localeName)),
    if (s.durationSeconds != null)
      formatClock(Duration(seconds: s.durationSeconds!)),
  ].join(' · ');
}

/// Rótulo da aba Check-ins com o badge de não revisados (P3.5 §3, Aceite
/// literal do P3.3: "não revisados primeiro" na fila — aqui é o mesmo
/// contador, só que no rótulo em vez da ordenação). `Consumer` isolado em
/// vez de converter a tela inteira para `ConsumerStatefulWidget`: só este
/// pedacinho precisa saber da contagem.
class CheckinsTabLabel extends ConsumerWidget {
  const CheckinsTabLabel({required this.studentId, super.key});

  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Não revisados + mídias sem ciência (P12.3).
    final pending =
        (ref.watch(checkinsProvider(studentId)).valueOrNull?.pendingCount ??
                0) +
            (ref.watch(coachMediaProvider(studentId)).valueOrNull?.pending
                    .length ??
                0);

    if (pending <= 0) return Text(l10n.evolutionTabCheckins);
    return Badge(
      label: Text(pending > 99 ? '99+' : pending.toString()),
      child: Text(l10n.evolutionTabCheckins),
    );
  }
}
