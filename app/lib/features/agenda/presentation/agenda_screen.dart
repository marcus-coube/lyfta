import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../domain/agenda_day.dart';
import 'agenda_controller.dart';
import 'widgets/agenda_day_cell.dart';
import 'widgets/agenda_day_details_sheet.dart';

/// Aba **Agenda** do aluno (P4.1): visão semanal (dom–sáb) do que já foi
/// treinado e do que a rotação projeta para os próximos dias, com um mês
/// expansível para navegar mais longe.
class AgendaScreen extends ConsumerWidget {
  const AgendaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(agendaControllerProvider);

    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorState(
        message: l10n.agendaLoadError,
        onRetry: () => ref.read(agendaControllerProvider.notifier).refresh(),
      ),
      data: (view) => RefreshIndicator(
        onRefresh: () => ref.read(agendaControllerProvider.notifier).refresh(),
        color: c.accent,
        child: ListView(
          padding: const EdgeInsets.all(LySpace.x4),
          children: [
            if (view.streakWeeks > 0) ...[
              _StreakBanner(weeks: view.streakWeeks),
              const SizedBox(height: LySpace.x4),
            ],
            _WeekNav(weekStart: view.weekStart),
            const SizedBox(height: LySpace.x3),
            _WeekStrip(days: view.weekDays),
            const SizedBox(height: LySpace.x4),
            Center(
              child: TextButton.icon(
                onPressed: () =>
                    ref.read(agendaControllerProvider.notifier).toggleMonth(),
                icon: Icon(
                  view.monthExpanded ? Icons.expand_less : Icons.expand_more,
                  color: c.textSecondary,
                ),
                label: Text(
                  view.monthExpanded
                      ? l10n.agendaCollapseMonth
                      : l10n.agendaExpandMonth,
                  style: LyType.bodySm(c.textSecondary),
                ),
              ),
            ),
            if (view.monthExpanded) ...[
              const SizedBox(height: LySpace.x2),
              _MonthGrid(focusedMonth: view.focusedMonth, days: view.monthDays),
            ],
            const SizedBox(height: LySpace.x12),
          ],
        ),
      ),
    );
  }
}

class _StreakBanner extends StatelessWidget {
  const _StreakBanner({required this.weeks});

  final int weeks;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return LyCard(
      padding: const EdgeInsets.symmetric(
        horizontal: LySpace.x4,
        vertical: LySpace.x3,
      ),
      child: Row(
        children: [
          Icon(Icons.local_fire_department_rounded, color: c.warning),
          const SizedBox(width: LySpace.x3),
          Expanded(
            child: Text(
              l10n.agendaStreakWeeks(weeks),
              style: LyType.body(c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekNav extends ConsumerWidget {
  const _WeekNav({required this.weekStart});

  final DateTime weekStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final weekEnd = weekStart.add(const Duration(days: 6));
    final notifier = ref.read(agendaControllerProvider.notifier);

    return Row(
      children: [
        IconButton(
          onPressed: notifier.previousWeek,
          tooltip: l10n.agendaPreviousWeek,
          icon: Icon(Icons.chevron_left, color: c.textPrimary),
        ),
        Expanded(
          child: Center(
            child: Text(
              l10n.agendaWeekRange(
                DateFormat.MMMd(locale).format(weekStart),
                DateFormat.MMMd(locale).format(weekEnd),
              ),
              style: LyType.title(c.textPrimary),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        IconButton(
          onPressed: notifier.nextWeek,
          tooltip: l10n.agendaNextWeek,
          icon: Icon(Icons.chevron_right, color: c.textPrimary),
        ),
      ],
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.days});

  final List<AgendaDay> days;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final day in days)
          Expanded(
            child: AgendaDayCell(
              date: day.date,
              state: day.state,
              label: day.dayLabel,
              selected: day.date == todayKey,
              onTap: () => showAgendaDayDetails(context, day),
            ),
          ),
      ],
    );
  }
}

class _MonthGrid extends ConsumerWidget {
  const _MonthGrid({required this.focusedMonth, required this.days});

  final DateTime focusedMonth;
  final List<AgendaDay> days;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final locale = Localizations.localeOf(context).toString();
    // A grade começa no domingo da semana do dia 1 (mesma convenção
    // dom–sáb da strip), preenchendo com espaços vazios os dias do mês
    // anterior que sobram na primeira linha.
    final firstOfMonth = DateTime(focusedMonth.year, focusedMonth.month);
    final leadingBlanks = firstOfMonth.weekday % 7;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat.yMMMM(locale).format(focusedMonth),
          style: LyType.title(c.textPrimary),
        ),
        const SizedBox(height: LySpace.x2),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
            for (final day in days)
              AgendaDayCell(
                date: day.date,
                state: day.state,
                label: day.dayLabel,
                dense: true,
                onTap: () => ref
                    .read(agendaControllerProvider.notifier)
                    .selectDay(day.date),
              ),
          ],
        ),
      ],
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
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
