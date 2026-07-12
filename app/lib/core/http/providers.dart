import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../config/app_config.dart';
import 'api_client.dart';
import 'token_storage.dart';

/// [TokenStorage] único, compartilhado por todos os [ApiClient]s (o refresh
/// token sempre é emitido pelo `identity`, mas vale para chamadas a qualquer
/// serviço — ADR-013).
final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

/// Cliente HTTP do serviço `identity` (auth, tenants, convites). Os demais
/// serviços (workout/assessment/comms) ganham providers análogos quando
/// tarefas futuras precisarem deles.
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
    onSessionExpired: () =>
        ref.read(authControllerProvider.notifier).signOut(),
  );
});
