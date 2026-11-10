import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/presentation/account_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/invite_accept_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/builder/presentation/plan_builder_screen.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/coach_shell/presentation/coach_shell_screen.dart';
import '../../features/consent/presentation/consent_screen.dart';
import '../../features/profile/presentation/my_goal_screen.dart';
import '../../features/student_shell/presentation/student_shell_screen.dart';
import '../../features/students/presentation/student_detail_screen.dart';
import '../../features/workout/presentation/session_player_screen.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_state.dart';

/// Rotas públicas — acessíveis mesmo sem sessão.
const _publicPaths = {'/login', '/signup', '/invite', '/forgot', '/reset'};

/// Router único do app. Redirect central decide:
/// - sem sessão (ou status ainda desconhecido) fora de rota pública → `/login`;
/// - sessão ativa em rota pública (ex.: usuário volta para `/login` já
///   logado) → `/home`;
/// - autenticado sem consentimento vigente → `/consent` (ADR-008 §1);
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
        // Gate de consentimento (ADR-008 §1, P4.5): sem consentimento vigente
        // na versão atual dos termos o usuário só enxerga a tela de
        // consentimento — nem o app, nem rota pública.
        final onConsent = state.matchedLocation == '/consent';
        if (authState.consentPending) return onConsent ? null : '/consent';
        if (onConsent) return '/home';
        // Convite aberto por quem já está logado (outra conta no mesmo
        // aparelho/navegador): mostra o convite em vez de ignorá-lo — a tela
        // avisa que ativar troca de conta (E2E P4.4).
        final token = state.uri.queryParameters['token'] ?? '';
        if (state.matchedLocation == '/invite' && token.isNotEmpty) {
          return null;
        }
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
        path: '/consent',
        builder: (context, state) => const ConsentScreen(),
      ),
      GoRoute(
        path: '/account',
        builder: (context, state) => const AccountScreen(),
      ),
      GoRoute(
        path: '/goal',
        builder: (context, state) => const MyGoalScreen(),
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
        // Token chega como query string (`/invite?token=...`). O link do
        // e-mail é web (APP_URL), então no celular ele abre o navegador: o
        // aluno aceita ali e depois entra no app com e-mail e senha. O
        // esquema `lyfta://` NÃO está registrado no AndroidManifest nem no
        // Info.plist — abrir o app direto pelo convite pede App Links /
        // Universal Links com domínio próprio (pendência pré-loja).
        // Chave pelo token: trocar de convite não reaproveita o formulário.
        builder: (context, state) => InviteAcceptScreen(
          key: ValueKey(state.uri.queryParameters['token']),
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
      // A ficha do aluno (dados, treino, evolução e check-ins) é rota de
      // primeira classe pelo mesmo motivo do builder: o professor abre, manda
      // o link para si mesmo e recarrega a página na web sem perder onde
      // estava. `?tab=` escolhe a aba (o push de check-in abre em `checkins`).
      GoRoute(
        path: '/students/:id',
        builder: (context, state) => StudentDetailScreen(
          studentId: state.pathParameters['id']!,
          studentName: state.extra as String?,
          initialTab: StudentTab.parse(state.uri.queryParameters['tab']),
        ),
      ),
      // Conversa própria pelo mesmo motivo do builder/evolução: recarregar
      // a página na web não pode perder o chat aberto.
      GoRoute(
        path: '/chat/:id',
        builder: (context, state) => ChatScreen(
          conversationId: state.pathParameters['id']!,
          title: state.extra as String?,
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
