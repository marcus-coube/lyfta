import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/domain/plan.dart';
import '../../../shared/l10n/plan_l10n.dart';
import '../../../shared/widgets/exercise_media.dart';
import '../data/workout_repository.dart';
import '../domain/today.dart';
import 'prescription_format.dart';
import 'session_controller.dart';
import 'today_controller.dart';
import 'widgets/sync_indicator.dart';

/// Tela **Hoje** do aluno (P1.7 §2) — a primeira coisa que ele vê.
///
/// Lê do banco local: se o treino já foi baixado, ela desenha igual sem
/// rede. A rede só decide se aparece o aviso de offline (ADR-003 §1).
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(todayControllerProvider);

    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorState(
        message: l10n.todayLoadError,
        onRetry: () => ref.read(todayControllerProvider.notifier).refresh(),
      ),
      data: (view) => RefreshIndicator(
        onRefresh: () => ref.read(todayControllerProvider.notifier).refresh(),
        color: c.accent,
        child: _TodayBody(view: view),
      ),
    );
  }
}

class _TodayBody extends ConsumerWidget {
  const _TodayBody({required this.view});

  final TodayView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final today = view.today;
    final openSession = ref.watch(sessionControllerProvider).valueOrNull;

    return Column(
      children: [
        if (view.stale) _OfflineBanner(message: l10n.todayOffline),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(LySpace.x4),
            children: [
              const SyncIndicator(),
              const SizedBox(height: LySpace.x3),
              switch (today.status) {
                TodayStatus.noPlan => _EmptyState(
                    icon: Icons.event_note_outlined,
                    title: l10n.todayNoPlanTitle,
                    body: l10n.todayNoPlanBody,
                  ),
                TodayStatus.restDay => _EmptyState(
                    icon: Icons.self_improvement_outlined,
                    title: l10n.todayRestTitle,
                    body: l10n.todayRestBody,
                  ),
                TodayStatus.ready => _DayCard(today: today),
              },
              if (today.rotation.length > 1) ...[
                const SizedBox(height: LySpace.x4),
                _RotationBar(today: today),
              ],
              if (today.recentSessions.isNotEmpty) ...[
                const SizedBox(height: LySpace.x6),
                _RecentSessions(sessions: today.recentSessions),
              ],
              const SizedBox(height: LySpace.x12),
            ],
          ),
        ),
        if (today.hasWorkout)
          _StartBar(today: today, hasOpenSession: openSession != null),
      ],
    );
  }
}

/// Cabeçalho do dia + os blocos com a prescrição de cada exercício.
class _DayCard extends StatelessWidget {
  const _DayCard({required this.today});

  final Today today;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final day = today.day!;
    final runs = today.runs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.todayDayHeading(day.label), style: LyType.h1(c.textPrimary)),
        if (day.title.isNotEmpty) ...[
          const SizedBox(height: LySpace.x1),
          Text(day.title, style: LyType.body(c.textSecondary)),
        ],
        const SizedBox(height: LySpace.x5),
        if (runs.isEmpty)
          Text(l10n.todayEmptyDay, style: LyType.body(c.textSecondary))
        else
          for (final run in runs) ...[
            _ExerciseRow(run: run, previous: today.previousLoads[run.exerciseId]),
            const SizedBox(height: LySpace.x3),
          ],
      ],
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.run, this.previous});

  final ExerciseRun run;
  final PreviousLoad? previous;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final exercise = run.exercise.exercise;
    final topLoad = previous?.topLoadKg;

    return LyCard(
      padding: const EdgeInsets.all(LySpace.x4),
      child: Row(
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
                const SizedBox(height: LySpace.x1),
                Text(
                  l10n.todaySetsCount(run.exercise.sets.length),
                  style: LyType.bodySm(c.textSecondary),
                ),
                if (run.exercise.sets.isNotEmpty) ...[
                  const SizedBox(height: LySpace.x1),
                  Text(
                    prescriptionLabel(l10n, run.exercise.sets.first),
                    style: LyType.bodySm(c.textSecondary),
                  ),
                ],
                const SizedBox(height: LySpace.x2),
                Wrap(
                  spacing: LySpace.x2,
                  runSpacing: LySpace.x1,
                  children: [
                    if (run.block.blockType != BlockType.straight)
                      _Chip(
                        label: blockTypeLabel(l10n, run.block.blockType),
                        color: c.info,
                      ),
                    _Chip(
                      label: topLoad == null
                          ? l10n.todayNoPreviousLoad
                          : l10n.todayPreviousLoad(formatLoad(topLoad)),
                      color: topLoad == null ? c.textSecondary : c.accent,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentSessions extends StatelessWidget {
  const _RecentSessions({required this.sessions});

  final List<SessionSummary> sessions;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.todayRecentTitle, style: LyType.title(c.textPrimary)),
        const SizedBox(height: LySpace.x2),
        for (final session in sessions)
          Padding(
            padding: const EdgeInsets.only(bottom: LySpace.x1),
            child: Text(
              l10n.todayRecentEntry(
                session.dayLabel,
                session.totalSets,
                formatLoad(session.totalVolumeKg),
              ),
              style: LyType.bodySm(c.textSecondary),
            ),
          ),
      ],
    );
  }
}

/// Barra fixa com o CTA do treino. Fica fora da lista de propósito: é a ação
/// principal da tela e não pode depender de rolar até o fim.
class _StartBar extends ConsumerWidget {
  const _StartBar({required this.today, required this.hasOpenSession});

  final Today today;
  final bool hasOpenSession;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return ColoredBox(
      color: c.background,
      child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(LySpace.x4),
        child: LyButton(
          label: hasOpenSession ? l10n.todayResume : l10n.todayStart,
          icon: Icon(hasOpenSession ? Icons.play_arrow : Icons.fitness_center),
          onPressed: () async {
            if (!hasOpenSession) {
              await ref.read(sessionControllerProvider.notifier).start(today);
            }
            if (context.mounted) unawaited(context.push('/session'));
          },
        ),
      ),
      ),
    );
  }
}

/// Onde a rotação aparece para o aluno: qual treino vem depois e o atalho
/// para trocar o de hoje (P1.8).
///
/// Fica fora do `_DayCard` porque vale também em dia de descanso — é ali que
/// antecipar o próximo treino faz mais sentido.
class _RotationBar extends ConsumerStatefulWidget {
  const _RotationBar({required this.today});

  final Today today;

  @override
  ConsumerState<_RotationBar> createState() => _RotationBarState();
}

class _RotationBarState extends ConsumerState<_RotationBar> {
  bool _switching = false;

  Future<void> _open() async {
    final l10n = AppLocalizations.of(context);
    final chosen = await showModalBottomSheet<RotationDay>(
      context: context,
      backgroundColor: context.ly.surface,
      showDragHandle: true,
      builder: (_) => _SwitchDaySheet(today: widget.today),
    );
    if (chosen == null || !mounted) return;

    setState(() => _switching = true);
    try {
      await ref.read(todayControllerProvider.notifier).overrideDay(chosen.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      // Rede é o caso comum aqui — a troca é a única ação do aluno que não
      // entra na fila offline (ADR-003 §1).
      final message = e.code == 'network_error'
          ? l10n.todaySwitchOffline
          : l10n.todaySwitchError;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final next = widget.today.nextDay;

    return LyCard(
      child: Row(
        children: [
          Expanded(
            child: next == null
                ? Text(l10n.todaySwitch, style: LyType.body(c.textSecondary))
                : Text(
                    l10n.todayNextWorkout(next.label),
                    style: LyType.body(c.textSecondary),
                  ),
          ),
          const SizedBox(width: LySpace.x3),
          if (_switching)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
            )
          else
            LyButton(
              label: l10n.todaySwitch,
              variant: LyButtonVariant.secondary,
              expanded: false,
              onPressed: _open,
            ),
        ],
      ),
    );
  }
}

/// Lista dos treinos do rodízio para o aluno escolher o de hoje.
class _SwitchDaySheet extends StatelessWidget {
  const _SwitchDaySheet({required this.today});

  final Today today;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final currentId = today.day?.id;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          LySpace.x4,
          0,
          LySpace.x4,
          LySpace.x4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.todaySwitchTitle, style: LyType.title(c.textPrimary)),
            const SizedBox(height: LySpace.x3),
            for (final day in today.rotation)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  l10n.todayDayHeading(day.label),
                  style: LyType.body(c.textPrimary),
                ),
                subtitle: day.title == null
                    ? null
                    : Text(day.title!, style: LyType.caption(c.textSecondary)),
                trailing: day.id == currentId
                    ? _Chip(label: l10n.todaySwitchCurrent, color: c.accent)
                    : const Icon(Icons.chevron_right),
                // O dia de hoje não é escolha: fechar sem nada evita um POST
                // que não muda coisa alguma.
                onTap: day.id == currentId
                    ? null
                    : () => Navigator.of(context).pop(day),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;

    return LyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c.textSecondary),
          const SizedBox(height: LySpace.x3),
          Text(title, style: LyType.title(c.textPrimary)),
          const SizedBox(height: LySpace.x2),
          Text(body, style: LyType.body(c.textSecondary)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LySpace.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: LyType.body(c.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: LySpace.x4),
            LyButton(
              label: l10n.commonRetry,
              variant: LyButtonVariant.secondary,
              expanded: false,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;

    return Container(
      width: double.infinity,
      color: c.surfaceElevated,
      padding: const EdgeInsets.symmetric(
        horizontal: LySpace.x4,
        vertical: LySpace.x2,
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 16, color: c.textSecondary),
          const SizedBox(width: LySpace.x2),
          Expanded(
            child: Text(message, style: LyType.caption(c.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LySpace.x2,
        vertical: LySpace.x1,
      ),
      decoration: BoxDecoration(
        borderRadius: LyRadius.pill,
        border: Border.all(color: color),
      ),
      child: Text(label, style: LyType.caption(color)),
    );
  }
}
