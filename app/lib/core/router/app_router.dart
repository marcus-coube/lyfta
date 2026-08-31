import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/invite_accept_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/builder/presentation/plan_builder_screen.dart';
import '../../features/coach_shell/presentation/coach_shell_screen.dart';
import '../../features/student_shell/presentation/student_shell_screen.dart';
import '../../features/workout/presentation/session_player_screen.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_state.dart';

/// Rotas públicas — acessíveis mesmo sem sessão.
const _publicPaths = {'/login', '/signup', '/invite', '/forgot', '/reset'};

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
        path: '/signup',
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: '/forgot',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset',
        builder: (context, state) => ResetPasswordScreen(
          token: state.uri.queryParameters['token'],
        ),
      ),
      GoRoute(
        path: '/invite',
        // Web: token chega como query string (`/invite?token=...`), lido
        // acima. Mobile: deep link `lyfta://invite?token=...` é registrado
        // nas plataformas nativas (AndroidManifest/Info.plist, geradas por
        // `flutter create .` — fora do que este repo versiona, ver
        // app/README.md) e o go_router resolve o mesmo `state.uri` a partir
        // do link recebido pelo SO, então nenhuma lógica extra é necessária
        // aqui além de configurar o esquema nas plataformas.
        builder: (context, state) => InviteAcceptScreen(
          token: state.uri.queryParameters['token'],
        ),
      ),
      // O builder é rota de primeira classe, não um push anônimo: na web o
      // professor precisa poder recarregar a página do plano que está
      // montando (e mandar o link para si mesmo).
      GoRoute(
        path: '/plans/:id',
        builder: (context, state) => PlanBuilderScreen(
          planId: state.pathParameters['id']!,
        ),
      ),
      // O player é rota própria pelo mesmo motivo do builder: recarregar a
      // página no meio do treino (web) não pode jogar o aluno para fora — a
      // sessão está no banco local e a tela se reconstrói a partir dele.
      GoRoute(
        path: '/session',
        builder: (context, state) => const SessionPlayerScreen(),
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
