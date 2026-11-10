import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/l10n/gen/app_localizations.dart';
import '../../../../shared/domain/plan.dart';
import '../../../../shared/l10n/plan_l10n.dart';
import '../../../../shared/widgets/exercise_media.dart';
import '../../domain/block_runner.dart';
import '../rest_timer_controller.dart';
import '../session_controller.dart';
import 'set_row.dart';

/// Cartão de um bloco conduzido (P6.5): bi-set e circuito por rodada,
/// drop set e rest-pause com as séries encadeadas. O registro de cada série
/// é o mesmo da linha do straight — só a ordem e o descanso vêm do
/// [BlockRunner].
class BlockCard extends ConsumerWidget {
  const BlockCard({required this.runner, required this.state, super.key});

  final BlockRunner runner;
  final SessionState state;

  bool _isDone(BlockStep s) => state.logFor(s.exerciseId, s.setNo) != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final current = runner.current(_isDone);

    return LyCard(
      padding: const EdgeInsets.all(LySpace.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            blockTypeLabel(l10n, runner.type),
            style: LyType.label(c.info),
          ),
          const SizedBox(height: LySpace.x1),
          Text(
            _methodText(l10n, runner.type),
            style: LyType.bodySm(c.textSecondary),
          ),
          const SizedBox(height: LySpace.x4),
          if (runner.isRounds)
            ..._rounds(context, ref, current)
          else
            ..._sequential(context, ref, current),
        ],
      ),
    );
  }

  List<Widget> _rounds(BuildContext context, WidgetRef ref, BlockStep? current) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final out = <Widget>[];
    for (var round = 0; round < runner.roundCount; round++) {
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: LySpace.x2),
          child: Text(
            l10n.sessionBlockRound(round + 1, runner.roundCount),
            style: LyType.title(c.textPrimary),
          ),
        ),
      );
      for (final step in runner.steps.where((s) => s.round == round)) {
        out.add(_stepTile(context, ref, step, current, showName: true));
      }
      out.add(const SizedBox(height: LySpace.x2));
    }
    return out;
  }

  List<Widget> _sequential(BuildContext context, WidgetRef ref, BlockStep? current) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final out = <Widget>[];
    for (final run in runner.runs) {
      final exercise = run.exercise.exercise;
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: LySpace.x2),
          child: Row(
            children: [
              if (exercise != null) ...[
                ExerciseMedia(exercise: exercise),
                const SizedBox(width: LySpace.x3),
              ],
              Expanded(
                child: Text(
                  exercise?.name ?? l10n.builderUnknownExercise,
                  style: LyType.title(c.textPrimary),
                ),
              ),
            ],
          ),
        ),
      );
      for (final step in runner.steps.where((s) => identical(s.run, run))) {
        out.add(_stepTile(context, ref, step, current, showName: false));
      }
      out.add(const SizedBox(height: LySpace.x2));
    }
    return out;
  }

  Widget _stepTile(
    BuildContext context,
    WidgetRef ref,
    BlockStep step,
    BlockStep? current, {
    required bool showName,
  }) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final exercise = step.run.exercise.exercise;
    final name = exercise?.name ?? l10n.builderUnknownExercise;
    final isCurrent = identical(step, current);
    final previous = state.today.previousLoads[step.exerciseId];

    return Container(
      key: ValueKey('block-step-${step.exerciseId}-${step.setNo}'),
      margin: const EdgeInsets.only(bottom: LySpace.x2),
      padding: const EdgeInsets.all(LySpace.x2),
      decoration: BoxDecoration(
        borderRadius: LyRadius.md,
        border: Border.all(
          color: isCurrent ? c.accent : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showName || isCurrent)
            Padding(
              padding: const EdgeInsets.only(bottom: LySpace.x2),
              child: Row(
                children: [
                  if (showName && exercise != null) ...[
                    ExerciseMedia(exercise: exercise),
                    const SizedBox(width: LySpace.x3),
                  ],
                  Expanded(
                    child: showName
                        ? Text(name, style: LyType.label(c.textPrimary))
                        : const SizedBox.shrink(),
                  ),
                  if (isCurrent)
                    Text(l10n.sessionBlockNow, style: LyType.caption(c.accent)),
                ],
              ),
            ),
          SetRow(
            setNo: step.setNo,
            prescribed: step.run.exercise.sets[step.setIndex],
            previous: previous?.setNoOrNull(step.setNo),
            logged: state.logFor(step.exerciseId, step.setNo),
            onLog: (reps, load, revises) =>
                _log(context, ref, step, reps, load, revises),
          ),
        ],
      ),
    );
  }

  Future<void> _log(
    BuildContext context,
    WidgetRef ref,
    BlockStep step,
    int? reps,
    double? load,
    String? revises,
  ) async {
    final l10n = AppLocalizations.of(context);
    unawaited(HapticFeedback.selectionClick());
    await ref.read(sessionControllerProvider.notifier).logSet(
          exerciseId: step.exerciseId,
          setNo: step.setNo,
          repsDone: reps,
          loadKg: load,
          revises: revises,
        );
    // Correção não reinicia o descanso (igual ao straight).
    if (revises != null) return;

    // A série recém-feita já conta como feita para achar a próxima.
    final next = runner.stepAfter(
      step.exerciseId,
      step.setNo,
      isDone: (s) => state.logFor(s.exerciseId, s.setNo) != null,
    );
    String nameOf(BlockStep s) =>
        s.run.exercise.exercise?.name ?? l10n.builderUnknownExercise;
    final label = nameOf(step);
    ref.read(restTimerProvider.notifier).start(
          rest: runner.restAfter(step.exerciseId, step.setNo),
          label: label,
          notificationTitle: l10n.sessionRestNotificationTitle,
          notificationBody:
              l10n.sessionRestNotificationBody(next == null ? label : nameOf(next)),
        );
  }
}

String _methodText(AppLocalizations l10n, BlockType type) => switch (type) {
      BlockType.superset => l10n.sessionBlockSuperset,
      BlockType.circuit => l10n.sessionBlockCircuit,
      BlockType.dropset => l10n.sessionBlockDropset,
      BlockType.restPause => l10n.sessionBlockRestPause,
      BlockType.straight => '',
    };
