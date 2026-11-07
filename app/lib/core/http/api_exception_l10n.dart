import 'package:flutter/widgets.dart';

import '../l10n/gen/app_localizations.dart';
import 'api_exception.dart';

/// Traduz o `code` estável do [ApiException] para mensagem i18n (ADR-011
/// §3: backend nunca traduz, cliente sempre traduz). Mantido fora da camada
/// de apresentação para ser reusado por qualquer feature que consuma a API.
extension ApiExceptionL10n on ApiException {
  String message(AppLocalizations l10n) {
    switch (code) {
      case 'invalid_credentials':
        return l10n.errorInvalidCredentials;
      case 'multiple_tenants':
        return l10n.errorMultipleTenants;
      case 'validation_error':
        return l10n.errorValidation(params['field']?.toString() ?? '');
      case 'email_taken':
        return l10n.errorEmailTaken;
      case 'invalid_token':
        return l10n.errorInvalidToken;
      case 'unauthenticated':
        return l10n.errorUnauthenticated;
      case 'forbidden':
        return l10n.errorForbidden;
      case 'slug_taken':
        return l10n.errorSlugTaken;
      case 'not_found':
        return l10n.errorNotFound;
      case 'invalid_cursor':
        return l10n.errorInvalidCursor;
      // Biblioteca e mídia (P1.2/P1.3).
      case 'exercise_is_global':
        return l10n.errorExerciseIsGlobal;
      case 'unsupported_media_type':
        return l10n.errorUnsupportedMedia;
      case 'file_too_large':
        return l10n.errorFileTooLarge;
      // Builder (P1.4): `reason` diz qual nível do plano ficou vazio.
      case 'plan_incomplete':
        return switch (params['reason']?.toString()) {
          'no_days' => l10n.errorPlanNoDays,
          'day_without_block' => l10n.errorPlanDayWithoutBlock,
          'block_without_exercise' => l10n.errorPlanBlockWithoutExercise,
          _ => l10n.errorPlanExerciseWithoutSet,
        };
      case 'no_draft_to_publish':
        return l10n.errorNoDraftToPublish;
      case 'unknown_exercise':
        return l10n.errorUnknownExercise;
      // Consentimento e exclusão de conta (ADR-008, P4.5).
      case 'consent_required':
        return l10n.errorConsentRequired;
      case 'terms_version_mismatch':
        return l10n.errorTermsVersionMismatch;
      case 'invalid_password':
        return l10n.errorInvalidPassword;
      case 'owner_cannot_delete':
        return l10n.errorOwnerCannotDelete;
      case 'erasure_failed':
        return l10n.errorErasureFailed;
      // Limite de tentativas (ADR-002 §2c): o backend manda os segundos até
      // liberar; a mensagem fala em minutos inteiros, arredondando para cima.
      case 'too_many_requests':
        final seconds = (params['retry_after_seconds'] as num?)?.toInt() ?? 300;
        return l10n.errorTooManyRequests(((seconds + 59) ~/ 60).clamp(1, 60));
      case 'network_error':
        return l10n.errorNetwork;
      case 'internal_error':
      default:
        return l10n.errorInternal;
    }
  }
}

/// Traduz qualquer erro que caia numa tela: [ApiException] vira mensagem pelo
/// `code`; o resto cai na mensagem genérica. Evita repetir o mesmo
/// `is ApiException ? ... : ...` em toda tela.
String describeApiError(BuildContext context, Object error) {
  final l10n = AppLocalizations.of(context);
  return error is ApiException ? error.message(l10n) : l10n.errorInternal;
}
