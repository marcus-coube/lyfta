import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../auth/auth_state.dart';
import '../http/providers.dart';
import 'comms_socket.dart';

/// O [CommsSocketService] do app inteiro — uma conexão só, reusada pela
/// lista de conversas (contador de não lidas do ícone da aba), pela tela de
/// uma conversa aberta e pela fila de check-ins do coach (P3.5). Conecta
/// quando a sessão autentica e desconecta no sign-out (mesmo padrão do
/// `WorkoutRepository.clearLocal` em `main.dart`, só que vivendo dentro do
/// provider em vez da raiz de composição — nada na UI precisa saber que
/// isto existe).
final commsSocketProvider = Provider<CommsSocketService>((ref) {
  final tokenStorage = ref.watch(tokenStorageProvider);
  final service = CommsSocketService(
    readAccessToken: () async => (await tokenStorage.read())?.accessToken,
    refreshAccessToken: () async {
      final stored = await tokenStorage.readSession();
      if (stored == null) return null;
      try {
        final tokens = await ref
            .read(authControllerProvider.notifier)
            .refreshSession(stored.tokens.refreshToken);
        return tokens.accessToken;
      } catch (_) {
        return null;
      }
    },
  );

  ref.listen<AuthState>(
    authControllerProvider,
    (previous, next) {
      if (next.status == AuthStatus.authenticated) {
        unawaited(service.connect());
      } else if (previous?.status == AuthStatus.authenticated) {
        service.disconnect();
      }
    },
    fireImmediately: true,
  );

  ref.onDispose(service.dispose);
  return service;
});
