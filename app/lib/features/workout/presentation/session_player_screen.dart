import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/domain/plan.dart';
import '../../../shared/l10n/plan_l10n.dart';
import '../../../shared/widgets/exercise_media.dart';
import '../../../shared/widgets/ly_shell_scaffold.dart';
import '../../checkin/presentation/checkin_sheet.dart';
import '../domain/today.dart';
import 'rest_timer_controller.dart';
import 'session_controller.dart';
import 'widgets/rest_timer_bar.dart';
import 'widgets/session_summary_sheet.dart';
import 'widgets/set_row.dart';

/// Player de execução (P1.7 §3): registrar série, descansar, finalizar.
///
/// Tudo aqui grava primeiro no banco local — a tela funciona igual em modo
/// avião, e é para isso que ela existe (ADR-003 §1).
class SessionPlayerScreen extends ConsumerStatefulWidget {
  const SessionPlayerScreen({super.key});

  @override
  ConsumerState<SessionPlayerScreen> createState() =>
      _SessionPlayerScreenState();
}

class _SessionPlayerScreenState extends ConsumerState<SessionPlayerScreen> {
  /// O rótulo do dia sobrevive ao fim da sessão: finalizar zera o estado, e
  /// sem isto o título viraria "Treino " enquanto o resumo está aberto.
  String _dayLabel = '';

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(sessionControllerProvider);
    _dayLabel = session.valueOrNull?.session.dayLabel ?? _dayLabel;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Text(l10n.sessionTitle(_dayLabel)),
        actions: [
          if (session.valueOrNull != null)
            TextButton(
              onPressed: () => _confirmFinish(context, ref),
              child: Text(l10n.sessionFinish),
            ),
        ],
      ),
      body: session.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const SizedBox.shrink(),
        data: (state) {
          if (state == null) return const SizedBox.shrink();
          return _SessionBody(state: state);
        },
      ),
    );
  }

  Future<void> _confirmFinish(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final state = ref.read(sessionControllerProvider).valueOrNull;
    if (state == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.sessionFinishTitle),
        content: Text(l10n.sessionFinishBody(state.completedSets)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.sessionFinish),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    ref.read(restTimerProvider.notifier).stop();
    final finished = await ref.read(sessionControllerProvider.notifier).finish();
    if (finished == null || !context.mounted) return;

    await showSessionSummary(context, finished);
    if (!context.mounted) return;
    // Avaliação estruturada do treino (P3.5 §2) — sempre depois do resumo,
    // nunca no lugar dele: o aluno primeiro vê o que fez, só depois avalia.
    await showCheckinSheet(context, sessionClientId: finished.session.clientId);
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _SessionBody extends ConsumerWidget {
  const _SessionBody({required this.state});

  final SessionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = state.today.runs;

    return Column(
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              // O player é uma coluna só em qualquer largura: na web, esticar
              // as linhas de série pela tela inteira afasta o campo de reps
              // do de carga sem ganhar nada.
              constraints: const BoxConstraints(maxWidth: lyShellRailBreakpoint),
              child: ListView.separated(
                padding: const EdgeInsets.all(LySpace.x4),
                itemCount: runs.length,
                separatorBuilder: (_, __) => const SizedBox(height: LySpace.x4),
                itemBuilder: (context, index) => _ExerciseCard(
                  run: runs[index],
                  state: state,
                ),
              ),
            ),
          ),
        ),
        const RestTimerBar(),
      ],
    );
  }
}

class _ExerciseCard extends ConsumerWidget {
  const _ExerciseCard({required this.run, required this.state});

  final ExerciseRun run;
  final SessionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final exercise = run.exercise.exercise;
    final previous = state.today.previousLoads[run.exerciseId];

    return LyCard(
      padding: const EdgeInsets.all(LySpace.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (exercise != null) ...[
                ExerciseMedia(exercise: exercise),
                const SizedBox(width: LySpace.x4),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise?.name ?? l10n.builderUnknownExercise,
                      style: LyType.title(c.textPrimary),
                    ),
                    if (run.block.blockType != BlockType.straight) ...[
                      const SizedBox(height: LySpace.x1),
                      Text(
                        blockTypeLabel(l10n, run.block.blockType),
                        style: LyType.caption(c.info),
                      ),
                    ],
                    if (run.exercise.notes.isNotEmpty) ...[
                      const SizedBox(height: LySpace.x1),
                      Text(
                        run.exercise.notes,
                        style: LyType.bodySm(c.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: LySpace.x4),
          for (var i = 0; i < run.exercise.sets.length; i++)
            SetRow(
              setNo: run.setNoAt(i),
              prescribed: run.exercise.sets[i],
              previous: previous?.setNoOrNull(run.setNoAt(i)),
              logged: state.logFor(run.exerciseId, run.setNoAt(i)),
              onLog: (reps, load, revises) => _log(
                context,
                ref,
                index: i,
                reps: reps,
                load: load,
                revises: revises,
                exerciseName: exercise?.name ?? l10n.builderUnknownExercise,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _log(
    BuildContext context,
    WidgetRef ref, {
    required int index,
    required int? reps,
    required double? load,
    required String? revises,
    required String exerciseName,
  }) async {
    final l10n = AppLocalizations.of(context);
    unawaited(HapticFeedback.selectionClick());
    await ref.read(sessionControllerProvider.notifier).logSet(
          exerciseId: run.exerciseId,
          setNo: run.setNoAt(index),
          repsDone: reps,
          loadKg: load,
          revises: revises,
        );
    // Corrigir uma série antiga não é motivo para começar a descansar de
    // novo — só a série recém-feita dispara o timer.
    if (revises != null) return;
    ref.read(restTimerProvider.notifier).start(
          rest: run.restAt(index),
          label: exerciseName,
          notificationTitle: l10n.sessionRestNotificationTitle,
          notificationBody: l10n.sessionRestNotificationBody(exerciseName),
        );
  }
}
