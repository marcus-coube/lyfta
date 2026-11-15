import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/l10n/plan_l10n.dart';
import '../../../shared/widgets/ly_error_state.dart';
import '../../../shared/widgets/ly_skeleton.dart';
import '../../workout/presentation/prescription_format.dart';
import '../../workout/presentation/widgets/session_summary_sheet.dart';
import '../domain/checkin.dart';
import '../domain/coach_session.dart';
import 'checkin_answers.dart';
import 'checkins_controller.dart';
import 'coach_checkins_tab.dart';
import 'coach_sessions_controller.dart';

/// Abaixo disso, coluna única; acima, tabela (P11.2 §2).
const double coachSessionWideBreakpoint = 840;

/// Detalhe do treino de um check-in, só leitura (P11.2 §2): métricas e
/// respostas no topo, depois bloco a bloco o prescrito × feito por série.
class CoachSessionScreen extends ConsumerWidget {
  const CoachSessionScreen({
    required this.studentId,
    required this.clientId,
    super.key,
  });

  final String studentId;
  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final key = (studentId: studentId, clientId: clientId);
    final detail = ref.watch(coachSessionDetailProvider(key));
    // O check-in vem da mesma fila da aba (mesmo provider): marcar como visto
    // aqui reflete lá. Fora das páginas já carregadas, o detalhe fica sem as
    // respostas.
    final checkins = ref.watch(checkinsProvider(studentId)).valueOrNull;
    final checkin =
        checkins?.items.where((c) => c.sessionClientId == clientId).firstOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.checkinDetailTitle)),
      body: detail.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(LySpace.x4),
          child: Column(
            children: [
              LySkeletonListTile(),
              SizedBox(height: LySpace.x4),
              LySkeletonListTile(),
            ],
          ),
        ),
        error: (error, _) => LyErrorState(
          message: describeApiError(context, error),
          retryable: isRetryableError(error),
          onRetry: () => ref.invalidate(coachSessionDetailProvider(key)),
        ),
        data: (data) => _Body(
          detail: data,
          checkin: checkin,
          onReview: checkin == null
              ? null
              : () => ref
                  .read(checkinsProvider(studentId).notifier)
                  .review(checkin.id),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.detail,
    required this.checkin,
    required this.onReview,
  });

  final CoachSessionDetail detail;
  final WorkoutCheckin? checkin;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final session = detail.session;
    final wide = MediaQuery.sizeOf(context).width >= coachSessionWideBreakpoint;
    final checkin = this.checkin;

    return ListView(
      padding: const EdgeInsets.all(LySpace.x4),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sessionTitleWithPlan(l10n, session),
                  style: LyType.h2(c.textPrimary),
                ),
                const SizedBox(height: LySpace.x4),
                SessionMetricsGrid(
                  metrics: session.metrics,
                  durationKnown: session.durationSeconds != null,
                ),
                if (checkin != null) ...[
                  const SizedBox(height: LySpace.x6),
                  Text(
                    l10n.checkinDetailAnswers,
                    style: LyType.label(c.textSecondary),
                  ),
                  const SizedBox(height: LySpace.x2),
                  CheckinAnswers(checkin: checkin),
                  const SizedBox(height: LySpace.x3),
                  if (checkin.isReviewed)
                    Row(
                      children: [
                        Icon(Icons.check_circle, size: 16, color: c.success),
                        const SizedBox(width: LySpace.x1),
                        Text(
                          l10n.checkinReviewed,
                          style: LyType.caption(c.success),
                        ),
                      ],
                    )
                  else
                    LyButton(
                      key: const Key('session_detail_review'),
                      label: l10n.checkinMarkReviewed,
                      variant: LyButtonVariant.secondary,
                      expanded: false,
                      onPressed: onReview,
                    ),
                ],
                for (final block in detail.blocks) ...[
                  const SizedBox(height: LySpace.x8),
                  Text(
                    blockTypeLabel(l10n, block.type),
                    style: LyType.caption(c.textSecondary),
                  ),
                  for (final exercise in block.exercises) ...[
                    const SizedBox(height: LySpace.x2),
                    _ExerciseCard(exercise: exercise, wide: wide),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.exercise, required this.wide});

  final CoachExercise exercise;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    // Largura total: a coluna pai alinha ao início e, no layout estreito,
    // nada aqui dentro estica — o card encolheria ao texto.
    return SizedBox(
      width: double.infinity,
      child: LyCard(
        padding: const EdgeInsets.all(LySpace.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(exercise.name, style: LyType.label(c.textPrimary)),
            const SizedBox(height: LySpace.x3),
            if (wide) ...[
              Row(
                children: [
                  _HeaderCell(l10n.checkinDetailColSet, 1),
                  _HeaderCell(l10n.checkinDetailColPrescribed, 3),
                  _HeaderCell(l10n.checkinDetailColDone, 3),
                ],
              ),
              const Divider(height: LySpace.x4),
            ],
            for (final set in exercise.sets)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: LySpace.x1),
                child: wide ? _WideSetRow(set: set) : _NarrowSetRow(set: set),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text, this.flex);

  final String text;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(text, style: LyType.caption(context.ly.textSecondary)),
    );
  }
}

String _doneText(AppLocalizations l10n, CoachSetDone done) {
  final parts = [
    if (done.repsDone != null) l10n.sessionTargetReps(done.repsDone!),
    if (done.loadKg != null)
      l10n.checkinDetailDoneLoad(formatLoad(done.loadKg!, l10n.localeName)),
    if (done.rpe != null)
      l10n.checkinDetailDoneRpe(formatLoad(done.rpe!, l10n.localeName)),
  ];
  return parts.isEmpty ? '—' : parts.join(' · ');
}

/// Rótulo, variação e marca de corrigida de uma série.
class _SetChips extends StatelessWidget {
  const _SetChips({required this.set});

  final CoachSet set;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final label = set.label;
    final variation = set.variationName;
    final revised = set.done?.revised ?? false;
    if (label == null && variation == null && !revised) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: LySpace.x2,
      runSpacing: LySpace.x1,
      children: [
        if (label != null && label.isNotEmpty)
          LyChip(
            key: const Key('session_set_label'),
            icon: Icons.label_outline,
            text: label,
            color: c.warning,
          ),
        if (variation != null)
          LyChip(
            key: const Key('session_set_variation'),
            icon: Icons.tune,
            text: variation,
            color: c.info,
          ),
        if (revised)
          LyChip(
            key: const Key('session_set_revised'),
            icon: Icons.edit_outlined,
            text: l10n.checkinDetailRevised,
            color: c.accent,
          ),
      ],
    );
  }
}

class _DoneText extends StatelessWidget {
  const _DoneText({required this.set});

  final CoachSet set;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final done = set.done;
    if (done == null) {
      return Text(
        l10n.checkinDetailNotDone,
        key: const Key('session_set_not_done'),
        style: LyType.bodySm(c.danger),
      );
    }
    return Text(_doneText(l10n, done), style: LyType.bodySm(c.textPrimary));
  }
}

class _WideSetRow extends StatelessWidget {
  const _WideSetRow({required this.set});

  final CoachSet set;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    return Row(
      key: const Key('session_set_row_wide'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            set.setNo.toString(),
            style: LyType.bodySm(c.textPrimary),
          ),
        ),
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                prescriptionLabel(l10n, set.prescribed),
                style: LyType.bodySm(c.textPrimary),
              ),
              _SetChips(set: set),
            ],
          ),
        ),
        Expanded(flex: 3, child: _DoneText(set: set)),
      ],
    );
  }
}

class _NarrowSetRow extends StatelessWidget {
  const _NarrowSetRow({required this.set});

  final CoachSet set;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    return Column(
      key: const Key('session_set_row_narrow'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.checkinDetailSetNo(set.setNo),
          style: LyType.caption(c.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          '${l10n.checkinDetailColPrescribed}: '
          '${prescriptionLabel(l10n, set.prescribed)}',
          style: LyType.bodySm(c.textPrimary),
        ),
        _DoneText(set: set),
        _SetChips(set: set),
        const SizedBox(height: LySpace.x2),
      ],
    );
  }
}
