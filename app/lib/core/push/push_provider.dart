import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_controller.dart';
import '../auth/auth_state.dart';
import '../router/app_router.dart';
import 'push_deep_link.dart';
import 'push_repository.dart';
import 'push_service.dart';

/// O [PushService] do app (P3.5 §4) — nasce lendo o [GoRouter] para saber
/// aonde levar quem tocou numa notificação, e se registra sozinho a cada vez
/// que a sessão autentica (mesmo padrão de auto-gestão do
/// `chatSocketProvider`/`commsSocketProvider`: nada na UI precisa lembrar de
/// chamar isto — só precisa existir, então `main.dart` faz um `ref.watch`
/// para instanciar).
final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService(repository: ref.watch(pushRepositoryProvider));
  final router = ref.watch(appRouterProvider);

  unawaited(
    service.init(onDeepLink: (link) => _handleDeepLink(router, link)),
  );

  ref.listen<AuthState>(
    authControllerProvider,
    (previous, next) {
      if (next.status == AuthStatus.authenticated) {
        unawaited(service.ensureRegistered());
      }
    },
    fireImmediately: true,
  );

  ref.onDispose(service.dispose);
  return service;
});

void _handleDeepLink(GoRouter router, PushDeepLink link) {
  switch (link.kind) {
    case PushDeepLinkKind.chat:
      router.push('/chat/${link.conversationId}');
    case PushDeepLinkKind.checkins:
      // Abre a ficha do aluno direto na aba Check-ins (P3.5 §3, P5.4).
      router.push('/students/${link.studentId}?tab=checkins');
    case PushDeepLinkKind.workoutToday:
      router.go('/home');
    case PushDeepLinkKind.none:
      break;
  }
}
