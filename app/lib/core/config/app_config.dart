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
}
