import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../config/app_config.dart';
import 'api_client.dart';
import 'token_storage.dart';

/// [TokenStorage] único, compartilhado por todos os [ApiClient]s (o refresh
/// token sempre é emitido pelo `identity`, mas vale para chamadas a qualquer
/// serviço — ADR-013).
final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

/// Cliente HTTP do serviço `identity` (auth, tenants, convites, usuários do
/// tenant). Cada serviço tem o seu (ADR-013), todos compartilhando o mesmo
/// [TokenStorage] e a mesma política de refresh.
///
/// O refresh chama o próprio `identity` via um [Dio] "cru" (sem os
/// interceptors deste client) para não reentrar no fluxo de refresh; ver
/// `AuthController._refresh`.
final identityApiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    baseUrl: AppConfig.identityBaseUrl,
    tokenStorage: ref.watch(tokenStorageProvider),
    refreshTokens: (refreshToken) =>
        ref.read(authControllerProvider.notifier).refreshSession(refreshToken),
    onSessionExpired: () => ref.read(authControllerProvider.notifier).signOut(),
  );
});

/// Cliente HTTP do serviço `workout` (biblioteca, planos, execução).
///
/// Mesma sessão do `identity`: o access token é o mesmo JWT, validado lá com
/// a chave pública (ADR-013 §4). O refresh continua batendo no `identity`,
/// que é quem assina — daí os dois clients compartilharem o [TokenStorage] e
/// o callback de refresh.
final workoutApiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    baseUrl: AppConfig.workoutBaseUrl,
    tokenStorage: ref.watch(tokenStorageProvider),
    refreshTokens: (refreshToken) =>
        ref.read(authControllerProvider.notifier).refreshSession(refreshToken),
    onSessionExpired: () => ref.read(authControllerProvider.notifier).signOut(),
  );
});

/// Cliente HTTP do serviço `assessment` (medidas, bioimpedância, fotos de
/// evolução — P2.2/P2.3). Mesma sessão dos demais: o `identity` é quem
/// assina o JWT que todo serviço valida (ADR-013 §4).
final assessmentApiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    baseUrl: AppConfig.assessmentBaseUrl,
    tokenStorage: ref.watch(tokenStorageProvider),
    refreshTokens: (refreshToken) =>
        ref.read(authControllerProvider.notifier).refreshSession(refreshToken),
    onSessionExpired: () => ref.read(authControllerProvider.notifier).signOut(),
  );
});

/// Cliente HTTP do serviço `comms` (chat, check-in de treino, devices —
/// P3.2/P3.3/P3.4). Mesma sessão dos demais.
final commsApiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    baseUrl: AppConfig.commsBaseUrl,
    tokenStorage: ref.watch(tokenStorageProvider),
    refreshTokens: (refreshToken) =>
        ref.read(authControllerProvider.notifier).refreshSession(refreshToken),
    onSessionExpired: () => ref.read(authControllerProvider.notifier).signOut(),
  );
});

/// Cliente HTTP do serviço `billing` (financeiro — ADR-017, P7.4). Mesma
/// sessão dos demais.
final billingApiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    baseUrl: AppConfig.billingBaseUrl,
    tokenStorage: ref.watch(tokenStorageProvider),
    refreshTokens: (refreshToken) =>
        ref.read(authControllerProvider.notifier).refreshSession(refreshToken),
    onSessionExpired: () => ref.read(authControllerProvider.notifier).signOut(),
  );
});
