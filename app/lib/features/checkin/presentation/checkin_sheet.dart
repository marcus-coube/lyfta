import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../domain/checkin.dart';
import 'checkin_controller.dart';

/// Abre a avaliação pós-treino (P3.5 §2) — chamada pelo player de execução
/// (`SessionPlayerScreen`) depois de `showSessionSummary`. `sessionClientId`
/// é o mesmo `client_id` da sessão finalizada (ADR-003 §2): é ele que faz o
/// check-in casar com o treino certo do lado do coach, sem FK entre bancos
/// (ADR-013 §2).
Future<void> showCheckinSheet(
  BuildContext context, {
  required String sessionClientId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (sheetContext) => _CheckinSheet(sessionClientId: sessionClientId),
  );
}

class _CheckinSheet extends ConsumerStatefulWidget {
  const _CheckinSheet({required this.sessionClientId});

  final String sessionClientId;

  @override
  ConsumerState<_CheckinSheet> createState() => _CheckinSheetState();
}

class _CheckinSheetState extends ConsumerState<_CheckinSheet> {
  int _rating = 3;
  int _difficulty = 3;
  PainLevel _pain = PainLevel.none;
  final _painNotes = TextEditingController();
  final _comment = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _painNotes.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    final draft = CheckinDraft(
      sessionClientId: widget.sessionClientId,
      rating: _rating,
      difficulty: _difficulty,
      pain: _pain,
      painNotes: _pain == PainLevel.none ? '' : _painNotes.text.trim(),
      comment: _comment.text.trim(),
    );
    final outcome = await ref.read(checkinControllerProvider.notifier).submit(draft);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          outcome == CheckinSubmitOutcome.sent
              ? l10n.checkinSubmitted
              : l10n.checkinQueuedOffline,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: LySpace.x6,
          right: LySpace.x6,
          top: LySpace.x6,
          bottom: LySpace.x6 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.checkinTitle, style: LyType.h2(c.textPrimary)),
              const SizedBox(height: LySpace.x2),
              Text(l10n.checkinSubtitle, style: LyType.bodySm(c.textSecondary)),
              const SizedBox(height: LySpace.x6),
              Text(l10n.checkinRatingLabel, style: LyType.label(c.textPrimary)),
              const SizedBox(height: LySpace.x2),
              _ScoreSelector(
                value: _rating,
                onChanged: (v) => setState(() => _rating = v),
              ),
              const SizedBox(height: LySpace.x5),
              Text(
                l10n.checkinDifficultyLabel,
                style: LyType.label(c.textPrimary),
              ),
              const SizedBox(height: LySpace.x2),
              _ScoreSelector(
                value: _difficulty,
                onChanged: (v) => setState(() => _difficulty = v),
              ),
              const SizedBox(height: LySpace.x5),
              Text(l10n.checkinPainLabel, style: LyType.label(c.textPrimary)),
              const SizedBox(height: LySpace.x2),
              SegmentedButton<PainLevel>(
                segments: [
                  ButtonSegment(
                    value: PainLevel.none,
                    label: Text(l10n.checkinPainNone),
                  ),
                  ButtonSegment(
                    value: PainLevel.mild,
                    label: Text(l10n.checkinPainMild),
                  ),
                  ButtonSegment(
                    value: PainLevel.strong,
                    label: Text(l10n.checkinPainStrong),
                  ),
                ],
                selected: {_pain},
                onSelectionChanged: (selection) =>
                    setState(() => _pain = selection.first),
              ),
              if (_pain != PainLevel.none) ...[
                const SizedBox(height: LySpace.x4),
                LyTextField(
                  label: l10n.checkinPainWhereLabel,
                  controller: _painNotes,
                ),
              ],
              const SizedBox(height: LySpace.x4),
              LyTextField(
                label: l10n.checkinCommentLabel,
                controller: _comment,
              ),
              const SizedBox(height: LySpace.x6),
              LyButton(
                label: l10n.checkinSubmit,
                loading: _saving,
                onPressed: _saving ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Seletor 1..5 (`rating`/`difficulty` do check-in, P3.3) — botões numerados
/// em vez de estrelas: mesma escala do servidor, sem inventar mapeamento
/// visual que precise de tradução.
class _ScoreSelector extends StatelessWidget {
  const _ScoreSelector({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;

    return Row(
      children: [
        for (var score = 1; score <= 5; score++) ...[
          if (score > 1) const SizedBox(width: LySpace.x2),
          Expanded(
            child: _ScoreButton(
              score: score,
              selected: score == value,
              onTap: () => onChanged(score),
              accent: c.accent,
              onAccent: c.onAccent,
              surface: c.surfaceElevated,
              border: c.border,
              text: c.textPrimary,
            ),
          ),
        ],
      ],
    );
  }
}

class _ScoreButton extends StatelessWidget {
  const _ScoreButton({
    required this.score,
    required this.selected,
    required this.onTap,
    required this.accent,
    required this.onAccent,
    required this.surface,
    required this.border,
    required this.text,
  });

  final int score;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;
  final Color onAccent;
  final Color surface;
  final Color border;
  final Color text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: LyRadius.md,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? accent : surface,
            borderRadius: LyRadius.md,
            border: Border.all(color: selected ? accent : border),
          ),
          child: Text(
            '$score',
            style: LyType.label(selected ? onAccent : text),
          ),
        ),
      ),
    );
  }
}
