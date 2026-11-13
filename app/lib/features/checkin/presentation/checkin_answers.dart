import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../domain/checkin.dart';

/// As respostas do aluno no check-in (notas, dor, comentário) — o card da
/// fila e o detalhe do treino mostram o mesmo bloco (P11.2).
class CheckinAnswers extends StatelessWidget {
  const CheckinAnswers({required this.checkin, super.key});

  final WorkoutCheckin checkin;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return Column(
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
      ],
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
