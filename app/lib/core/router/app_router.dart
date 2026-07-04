import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/invite_accept_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/coach_shell/presentation/coach_shell_screen.dart';
import '../../features/student_shell/presentation/student_shell_screen.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_state.dart';

/// Rotas públicas — acessíveis mesmo sem sessão.
const _publicPaths = {'/login', '/invite', '/forgot'};

/// Router único do app. Redirect central decide:
/// - sem sessão (ou status ainda desconhecido) fora de rota pública → `/login`;
/// - sessão ativa em rota pública (ex.: usuário volta para `/login` já
///   logado) → `/home`;
/// - `/home` escolhe o shell pelo [ActiveContext] atual (coach × student).
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    debugLogDiagnostics: kDebugMode,
    refreshListenable: _AuthChangeNotifier(ref),
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      final isPublic = _publicPaths.contains(state.matchedLocation);

      if (authState.status == AuthStatus.authenticated) {
        return isPublic ? '/home' : null;
      }

      // unknown ou unauthenticated: só rotas públicas são permitidas.
      return isPublic ? null : '/login';
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/forgot',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/invite',
        builder: (context, state) => InviteAcceptScreen(
          token: state.uri.queryParameters['token'],
        ),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) {
          final activeContext = ref.read(authControllerProvider).activeContext;
          return activeContext == ActiveContext.student
              ? const StudentShellScreen()
              : const CoachShellScreen();
        },
      ),
    ],
  );
});

/// Ponte entre `Riverpod` (estado de auth) e `Listenable` (o que `go_router`
/// espera em `refreshListenable`) — reavalia o redirect a cada mudança de
/// [AuthState].
class _AuthChangeNotifier extends ChangeNotifier {
  _AuthChangeNotifier(Ref ref) {
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      notifyListeners();
    });
  }
}
