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
      case 'network_error':
        return l10n.errorNetwork;
      case 'internal_error':
      default:
        return l10n.errorInternal;
    }
  }
}
