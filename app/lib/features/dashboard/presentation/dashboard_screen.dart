import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/ly_error_state.dart';
import '../../../shared/widgets/ly_skeleton.dart';
import '../../billing/presentation/billing_format.dart';
import '../domain/dashboard_models.dart';
import 'dashboard_providers.dart';

/// Largura a partir da qual os cards formam grade (mesmo corte do shell).
const double dashboardGridBreakpoint = 840;

/// Linhas por lista de aluno antes do "+N".
const int _maxRows = 6;

/// Primeira aba do shell do professor (P8.2): o estado do dia e, para o owner,
/// do negócio. Cada card tem o próprio provider — carrega, falha e tenta de
/// novo sozinho, então um serviço fora do ar não derruba os outros (P4.2).
/// Valores financeiros só para o owner (o coach nem chama o `billing`).
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = ref.watch(authControllerProvider).isOwner;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= dashboardGridBreakpoint;
        const gap = LySpace.x4;
        final cardWidth = wide
            ? (constraints.maxWidth - LySpace.x6 * 2 - gap) / 2
            : constraints.maxWidth;

        Widget sized(Widget card, {bool full = false}) => SizedBox(
              width: full && wide ? cardWidth * 2 + gap : cardWidth,
              child: card,
            );

        return ListView(
          padding: const EdgeInsets.all(LySpace.x6),
          children: [
            if (isOwner) const _CoachFilter(),
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                sized(const _StudentsCard()),
                sized(const _CheckinsCard()),
                sized(const _TodayCard()),
                sized(const _StalledCard()),
                if (isOwner) ...[
                  sized(const _BillingCard(), full: true),
                  sized(const _SeriesCard(), full: true),
                ],
              ],
            ),
          ],
        );
      },
    );
  }
}

class _CoachFilter extends ConsumerWidget {
  const _CoachFilter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final coaches = ref.watch(dashboardCoachOptionsProvider).valueOrNull;
    if (coaches == null || coaches.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: LySpace.x4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: DropdownButton<String?>(
          key: const Key('dashboard_filter_coach'),
          value: ref.watch(dashboardCoachFilterProvider),
          hint: Text(l10n.studentsFilterCoachLabel),
          underline: const SizedBox.shrink(),
          style: LyType.body(c.textPrimary),
          onChanged: (value) =>
              ref.read(dashboardCoachFilterProvider.notifier).state = value,
          items: [
            DropdownMenuItem<String?>(
              child: Text(l10n.studentsFilterCoachAll),
            ),
            for (final coach in coaches)
              DropdownMenuItem<String?>(
                value: coach.id,
                child: Text(coach.name),
              ),
          ],
        ),
      ),
    );
  }
}

/// Moldura de um card: título + (skeleton | erro com retry | conteúdo).
class _DashCard<T> extends ConsumerWidget {
  const _DashCard({
    required this.cardKey,
    required this.title,
    required this.provider,
    required this.builder,
  });

  final String cardKey;
  final String title;
  final ProviderBase<AsyncValue<T>> provider;
  final Widget Function(BuildContext context, T data) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;

    return KeyedSubtree(
      key: Key(cardKey),
      child: LyCard(
        padding: const EdgeInsets.all(LySpace.x5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: LyType.label(c.textSecondary)),
            const SizedBox(height: LySpace.x3),
            ref.watch(provider).when(
                  loading: () => const _CardSkeleton(),
                  error: (error, _) => LyErrorState(
                    message: describeApiError(context, error),
                    onRetry: () => ref.invalidate(provider),
                  ),
                  data: (data) => builder(context, data),
                ),
          ],
        ),
      ),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LySkeletonLine(width: 80, height: 28),
          SizedBox(height: LySpace.x3),
          LySkeletonLine(width: 160),
        ],
      );
}

class _BigNumber extends StatelessWidget {
  const _BigNumber(this.value, {this.color});

  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        value,
        style: LyType.numeric(color ?? context.ly.textPrimary, size: 32),
      );
}

// ---- Alunos ativos ----

class _StudentsCard extends StatelessWidget {
  const _StudentsCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ly;
    return _DashCard<StudentStats>(
      cardKey: 'dashboard_card_students',
      title: l10n.dashboardCardStudents,
      provider: dashboardStudentStatsProvider,
      builder: (context, stats) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BigNumber('${stats.active}'),
          const SizedBox(height: LySpace.x2),
          Text(
            l10n.dashboardStudentsNew(stats.newThisMonth),
            style: LyType.bodySm(c.textSecondary),
          ),
          Text(
            l10n.dashboardStudentsPending(stats.pendingInvites),
            style: LyType.bodySm(c.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ---- Check-ins não revisados ----

class _CheckinsCard extends StatelessWidget {
  const _CheckinsCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ly;
    return _DashCard<int>(
      cardKey: 'dashboard_card_checkins',
      title: l10n.dashboardCardCheckins,
      provider: dashboardCheckinsProvider,
      builder: (context, unreviewed) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BigNumber(
            '$unreviewed',
            color: unreviewed > 0 ? c.warning : null,
          ),
          if (unreviewed == 0) ...[
            const SizedBox(height: LySpace.x2),
            Text(
              l10n.dashboardCheckinsZero,
              style: LyType.bodySm(c.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

// ---- Treinos de hoje / sem treinar ----

/// Ids ordenados: a chave estável da busca de nomes.
List<String> _ids(Iterable<TodayItem> items) =>
    ([for (final i in items) i.studentId]..sort());

class _TodayCard extends StatelessWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ly;
    return _DashCard<CoachToday>(
      cardKey: 'dashboard_card_today',
      title: l10n.dashboardCardToday,
      provider: dashboardTodayProvider,
      builder: (context, today) {
        final listed = today.listed;
        final noPlan = today.count(TodayState.noPlan);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: LySpace.x6,
              runSpacing: LySpace.x3,
              children: [
                _Counter(
                  label: l10n.dashboardTodayTrained,
                  value: today.count(TodayState.trained),
                  color: c.success,
                ),
                _Counter(
                  label: l10n.dashboardTodayInProgress,
                  value: today.count(TodayState.inProgress),
                  color: c.info,
                ),
                _Counter(
                  label: l10n.dashboardTodayPending,
                  value: today.count(TodayState.pending),
                  color: c.warning,
                ),
              ],
            ),
            const SizedBox(height: LySpace.x3),
            if (listed.isEmpty)
              Text(
                l10n.dashboardTodayEmpty,
                style: LyType.bodySm(c.textSecondary),
              )
            else
              _StudentRows(
                items: listed,
                trailing: (item) => _StateChip(item.state),
              ),
            if (noPlan > 0) ...[
              const SizedBox(height: LySpace.x2),
              Text(
                l10n.dashboardTodayNoPlan(noPlan),
                style: LyType.bodySm(c.textSecondary),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _StalledCard extends StatelessWidget {
  const _StalledCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ly;
    return _DashCard<CoachToday>(
      cardKey: 'dashboard_card_stalled',
      title: l10n.dashboardCardStalled,
      provider: dashboardTodayProvider,
      builder: (context, today) {
        final stalled = today.stalled;
        if (stalled.isEmpty) {
          return Text(
            l10n.dashboardStalledEmpty,
            style: LyType.bodySm(c.textSecondary),
          );
        }
        return _StudentRows(
          items: stalled,
          trailing: (item) {
            final last = item.lastSessionAt!;
            final now = DateTime.now();
            final days = DateTime(now.year, now.month, now.day)
                .difference(DateTime(last.year, last.month, last.day))
                .inDays;
            return Text(
              l10n.studentsLastWorkoutDaysAgo(days),
              style: LyType.bodySm(c.textSecondary),
            );
          },
        );
      },
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: LyType.numeric(color, size: 28)),
          Text(label, style: LyType.bodySm(context.ly.textSecondary)),
        ],
      );
}

class _StateChip extends StatelessWidget {
  const _StateChip(this.state);

  final TodayState state;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final (label, color) = switch (state) {
      TodayState.trained => (l10n.dashboardTodayTrained, c.success),
      TodayState.inProgress => (l10n.dashboardTodayInProgress, c.info),
      _ => (l10n.dashboardTodayPending, c.warning),
    };
    return Text(label, style: LyType.label(color));
  }
}

/// Linhas "nome + indicador" que abrem a ficha do aluno; ≥ 48 dp de toque.
class _StudentRows extends ConsumerWidget {
  const _StudentRows({required this.items, required this.trailing});

  final List<TodayItem> items;
  final Widget Function(TodayItem item) trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final shown = items.take(_maxRows).toList();
    final names =
        ref.watch(dashboardNamesProvider(_ids(shown).join(','))).valueOrNull ??
            const <String, String>{};

    return Column(
      children: [
        for (final item in shown)
          InkWell(
            key: Key('dashboard_student_${item.studentId}'),
            onTap: () => context.push(
              '/students/${item.studentId}',
              extra: names[item.studentId],
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      names[item.studentId] ?? l10n.dashboardStudentUnknown,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LyType.body(c.textPrimary),
                    ),
                  ),
                  const SizedBox(width: LySpace.x3),
                  trailing(item),
                ],
              ),
            ),
          ),
        if (items.length > shown.length)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: LySpace.x1),
              child: Text(
                l10n.dashboardMore(items.length - shown.length),
                style: LyType.bodySm(c.textSecondary),
              ),
            ),
          ),
      ],
    );
  }
}

// ---- Financeiro (só owner) ----

class _BillingCard extends StatelessWidget {
  const _BillingCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ly;
    return _DashCard<BillingSummary>(
      cardKey: 'dashboard_card_billing',
      title: periodHeader(context),
      provider: dashboardBillingProvider,
      builder: (context, s) {
        Widget tile(String label, String value, String detail,
                {Color? color,}) =>
            SizedBox(
              width: 200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: LyType.bodySm(c.textSecondary)),
                  Text(value, style: LyType.numeric(color ?? c.textPrimary)),
                  Text(detail, style: LyType.caption(c.textSecondary)),
                ],
              ),
            );
        return Wrap(
          spacing: LySpace.x6,
          runSpacing: LySpace.x4,
          children: [
            tile(
              l10n.dashboardCardReceived,
              moneyText(context, s.receivedCents, currency: s.currency),
              '',
              color: c.success,
            ),
            tile(
              l10n.dashboardCardToReceive,
              moneyText(context, s.toReceiveCents, currency: s.currency),
              l10n.dashboardInvoicesCount(s.toReceiveCount),
            ),
            tile(
              l10n.dashboardCardOverdue,
              moneyText(context, s.overdueCents, currency: s.currency),
              l10n.dashboardInvoicesCount(s.overdueCount),
              color: s.overdueCents > 0 ? c.danger : null,
            ),
            tile(
              l10n.dashboardCardDelinquent,
              '${s.delinquentStudents}',
              l10n.dashboardStudentsCount(s.delinquentStudents),
              color: s.delinquentStudents > 0 ? c.danger : null,
            ),
          ],
        );
      },
    );
  }

  /// O título do card é o mês corrente ("novembro de 2026").
  static String periodHeader(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.yMMMM(locale).format(DateTime.now());
  }
}

class _SeriesCard extends StatelessWidget {
  const _SeriesCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _DashCard<BillingSummary>(
      cardKey: 'dashboard_card_series',
      title: l10n.dashboardCardSeries,
      provider: dashboardBillingProvider,
      builder: (context, s) =>
          SizedBox(height: 200, child: _ReceivedChart(summary: s)),
    );
  }
}

class _ReceivedChart extends StatelessWidget {
  const _ReceivedChart({required this.summary});

  final BillingSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final locale = Localizations.localeOf(context).toString();
    final series = summary.series;
    // O gráfico é o único lugar onde o centavo vira `double` — só para
    // desenhar (ADR-007); o valor exibido sai de `moneyText` (inteiro).
    final maxY = series.fold<int>(
        0, (m, p) => p.receivedCents > m ? p.receivedCents : m,);

    String month(String period) {
      final y = int.tryParse(period.substring(0, 4));
      final m = int.tryParse(period.substring(5, 7));
      if (y == null || m == null) return period;
      return DateFormat.MMM(locale).format(DateTime(y, m));
    }

    return BarChart(
      BarChartData(
        maxY: maxY == 0 ? 1 : maxY / 100 * 1.15,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(),
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= series.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: LySpace.x2),
                  child: Text(
                    month(series[i].period),
                    style: LyType.caption(c.textSecondary),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                BarTooltipItem(
              moneyText(
                context,
                series[groupIndex].receivedCents,
                currency: summary.currency,
              ),
              LyType.label(c.textPrimary),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < series.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: series[i].receivedCents / 100,
                  width: 18,
                  color: i == series.length - 1 ? c.accent : c.info,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
