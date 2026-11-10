import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/ly_error_state.dart';
import '../../../shared/widgets/ly_skeleton.dart';
import '../domain/checkin.dart';
import 'checkins_controller.dart';

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
        if (state.items.isEmpty) {
          return Center(
            child: Text(
              l10n.checkinListEmpty,
              style: LyType.body(c.textSecondary),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () =>
              ref.read(checkinsProvider(studentId).notifier).refresh(),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              LySpace.x4,
              LySpace.x4,
              LySpace.x4,
              LySpace.x16,
            ),
            itemCount: state.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: LySpace.x3),
            itemBuilder: (context, index) => _CheckinCard(
              checkin: state.items[index],
              onReview: () => ref
                  .read(checkinsProvider(studentId).notifier)
                  .review(state.items[index].id),
            ),
          ),
        );
      },
    );
  }
}

class _CheckinCard extends StatelessWidget {
  const _CheckinCard({required this.checkin, required this.onReview});

  final WorkoutCheckin checkin;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return LyCard(
      padding: const EdgeInsets.all(LySpace.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.checkinCardScores(checkin.rating, checkin.difficulty),
                  style: LyType.label(c.textPrimary),
                ),
              ),
              _PainBadge(pain: checkin.pain),
            ],
          ),
          const SizedBox(height: LySpace.x1),
          Text(
            _dateLabel(context, checkin.createdAt),
            style: LyType.caption(c.textSecondary),
          ),
          if (checkin.painNotes.isNotEmpty) ...[
            const SizedBox(height: LySpace.x2),
            Text(
              l10n.checkinCardPainWhere(checkin.painNotes),
              style: LyType.bodySm(c.textPrimary),
            ),
          ],
          if (checkin.comment.isNotEmpty) ...[
            const SizedBox(height: LySpace.x2),
            Text(checkin.comment, style: LyType.bodySm(c.textPrimary)),
          ],
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

  /// Dia/mês e hora na ordem do locale (`07/11 16:16` em pt, `11/7 4:16 PM`
  /// em en) — antes era `dd/MM` fixo e o inglês lia 11 de julho (E2E P4.4).
  String _dateLabel(BuildContext context, DateTime dt) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.Md(locale).add_jm().format(dt.toLocal());
  }
}

class _PainBadge extends StatelessWidget {
  const _PainBadge({required this.pain});

  final PainLevel pain;

  @override
  Widget build(BuildContext context) {
    if (pain == PainLevel.none) return const SizedBox.shrink();
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final color = pain == PainLevel.strong ? c.danger : c.warning;
    final label = pain == PainLevel.strong
        ? l10n.checkinPainStrong
        : l10n.checkinPainMild;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: LySpace.x2, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: LyRadius.pill,
      ),
      child: Text(label, style: LyType.caption(color)),
    );
  }
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
    final pending =
        ref.watch(checkinsProvider(studentId)).valueOrNull?.pendingCount ?? 0;

    if (pending <= 0) return Text(l10n.evolutionTabCheckins);
    return Badge(
      label: Text(pending > 99 ? '99+' : pending.toString()),
      child: Text(l10n.evolutionTabCheckins),
    );
  }
}
