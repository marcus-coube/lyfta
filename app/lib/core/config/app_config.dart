/// Configuração de ambiente do app — URLs base dos serviços do backend.
///
/// Cada serviço (ADR-013) é resolvido via `--dart-define` com fallback para
/// `localhost` nas portas do `backend/README.md`. Exemplo de uso:
/// ```
/// flutter run -d chrome --dart-define=IDENTITY_BASE_URL=https://identity.lyfta.app
/// ```
class AppConfig {
  const AppConfig._();

  static const String identityBaseUrl = String.fromEnvironment(
    'IDENTITY_BASE_URL',
    defaultValue: 'http://localhost:8081',
  );

  static const String workoutBaseUrl = String.fromEnvironment(
    'WORKOUT_BASE_URL',
    defaultValue: 'http://localhost:8082',
  );

  static const String assessmentBaseUrl = String.fromEnvironment(
    'ASSESSMENT_BASE_URL',
    defaultValue: 'http://localhost:8083',
  );

  static const String commsBaseUrl = String.fromEnvironment(
    'COMMS_BASE_URL',
    defaultValue: 'http://localhost:8084',
  );

  static const String billingBaseUrl = String.fromEnvironment(
    'BILLING_BASE_URL',
    defaultValue: 'http://localhost:8085',
  );

  /// Versão vigente dos termos de uso e da política de privacidade
  /// (ADR-008 §6). Tem de ser a mesma do `TERMS_VERSION` do `identity` e a que
  /// consta nos textos de `assets/legal/` — o backend recusa o aceite com
  /// outra versão (`terms_version_mismatch`).
  static const String termsVersion = String.fromEnvironment(
    'TERMS_VERSION',
    defaultValue: '2026-11-v1',
  );

  /// DSN do Sentry/GlitchTip (ADR-009 §5, P4.6). Vazio = desligado: dev e CI
  /// não mandam nada, o erro só aparece no console.
  static const String sentryDsn = String.fromEnvironment('SENTRY_DSN');

  /// Ambiente do evento (`production`, `staging`...).
  static const String sentryEnvironment = String.fromEnvironment(
    'SENTRY_ENVIRONMENT',
    defaultValue: 'development',
  );

  /// Release do evento, no formato `<version>+<build>` — manter igual ao
  /// `version:` do pubspec.yaml ao virar release (P4.4).
  static const String appRelease = String.fromEnvironment(
    'APP_RELEASE',
    defaultValue: '1.0.0+1',
  );
}
