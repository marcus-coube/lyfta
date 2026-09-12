import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/l10n/gen/app_localizations.dart';
import '../../domain/agenda_day.dart';

/// Uma célula de dia da agenda — widget "burro" (só dados + callback, mesma
/// convenção do `ChatBubble`/P2.4): não conhece controller nem API, só o que
/// precisa desenhar. É o que o teste de widget do Aceite (P4.1: "3 estados")
/// monta sem subir provider nenhum.
///
/// Os três estados são visualmente distintos por forma, não só por cor —
/// contraste AA e daltonismo não podem depender só do preenchimento
/// (docs/guidelines/flutter.md § i18n & acessibilidade):
/// - [AgendaDayState.done]: círculo preenchido com um check.
/// - [AgendaDayState.predicted]: círculo só com borda, mostrando o rótulo do
///   rodízio (A/B/C…).
/// - [AgendaDayState.rest]: sem círculo, um traço discreto.
class AgendaDayCell extends StatelessWidget {
  const AgendaDayCell({
    required this.date,
    required this.state,
    super.key,
    this.label,
    this.selected = false,
    this.dense = false,
    this.onTap,
  });

  final DateTime date;
  final AgendaDayState state;

  /// Rótulo do rodízio (A/B/C…) — mostrado dentro do indicador quando
  /// [state] é [AgendaDayState.predicted]; ignorado nos outros estados.
  final String? label;

  /// É o dia da semana atualmente em foco na strip.
  final bool selected;

  /// Versão compacta (sem dia da semana nem número) para a grade do mês.
  final bool dense;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();

    final String stateDescription = switch (state) {
      AgendaDayState.done => l10n.agendaStateDone,
      AgendaDayState.predicted => l10n.agendaStatePredicted,
      AgendaDayState.rest => l10n.agendaStateRest,
    };

    final double size = dense ? 22 : 34;
    final Widget indicator = switch (state) {
      AgendaDayState.done => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.success),
          alignment: Alignment.center,
          child: Icon(
            Icons.check_rounded,
            size: dense ? 12 : 18,
            color: c.onAccent,
          ),
        ),
      AgendaDayState.predicted => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: c.accent, width: 1.5),
          ),
          alignment: Alignment.center,
          child:
              dense ? null : Text(label ?? '', style: LyType.label(c.accent)),
        ),
      AgendaDayState.rest => SizedBox(
          width: size,
          height: size,
          child: Icon(
            Icons.remove_rounded,
            size: dense ? 12 : 16,
            color: c.textSecondary,
          ),
        ),
    };

    final ring = selected
        ? BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: c.textPrimary, width: 1.5),
          )
        : null;

    final body = dense
        ? indicator
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _weekdayAbbrev(locale, date),
                style: LyType.caption(c.textSecondary),
              ),
              const SizedBox(height: LySpace.x1),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: ring,
                child: indicator,
              ),
              const SizedBox(height: LySpace.x1),
              Text(
                DateFormat.d(locale).format(date),
                style: LyType.bodySm(c.textPrimary),
              ),
            ],
          );

    return Semantics(
      label: '${DateFormat.yMMMd(locale).format(date)} — $stateDescription',
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: LyRadius.md,
        child: Padding(
          padding: EdgeInsets.all(dense ? LySpace.x1 : LySpace.x2),
          child: body,
        ),
      ),
    );
  }

  String _weekdayAbbrev(String locale, DateTime date) {
    final abbrev = DateFormat.E(locale).format(date);
    return abbrev.length <= 3 ? abbrev : abbrev.substring(0, 3);
  }
}
