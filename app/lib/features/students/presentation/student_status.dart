import '../../../core/l10n/gen/app_localizations.dart';

/// Rótulo traduzido do status do aluno (códigos estáveis do `identity`).
String studentStatusLabel(AppLocalizations l10n, String status) {
  return switch (status) {
    'active' => l10n.studentStatusActive,
    'inactive' => l10n.studentStatusInactive,
    'invited' => l10n.studentStatusInvited,
    _ => l10n.studentStatusDisabled,
  };
}
