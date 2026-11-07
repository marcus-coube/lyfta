import 'package:flutter/widgets.dart';

import '../../core/design_system/design_system.dart';
import '../../core/l10n/gen/app_localizations.dart';

/// Estado de erro com ação de tentar de novo (P4.2 §3) — mensagem sempre
/// traduzida (nunca stack/erro cru, ADR-011 §3: quem chama já resolveu o
/// `code` via `describeApiError`) e um botão que refaz a chamada.
///
/// Compartilhado porque a partir da P4.2 passou a repetir em telas de
/// features diferentes (chat, alunos, check-ins); `_ErrorState` local segue
/// existindo em telas mais antigas (Hoje/Biblioteca/Agenda) — não são
/// tocadas aqui para não regredir o que já está testado.
class LyErrorState extends StatelessWidget {
  const LyErrorState({
    required this.message,
    required this.onRetry,
    this.retryable = true,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  /// Falso para erro que repetir não resolve (ex.: `student_not_found`): some
  /// o botão e fica só a mensagem.
  final bool retryable;

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
              textAlign: TextAlign.center,
              style: LyType.body(c.textSecondary),
            ),
            if (retryable) ...[
              const SizedBox(height: LySpace.x4),
              LyButton(
                label: l10n.commonRetry,
                variant: LyButtonVariant.secondary,
                expanded: false,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
