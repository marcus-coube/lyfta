import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_state.dart';

/// Controlador de sessão consumido pelo `go_router` para redirect e pelos
/// shells para decidir qual navegação mostrar.
///
/// **Stub por ora:** começa `unauthenticated` (sem persistência real ainda).
/// P0.6 troca a implementação para ler o `TokenStorage`/chamar o `identity`
/// no boot, mantendo esta mesma interface (`state`, [signInStub],
/// [signOut], [switchContext]) — quem depende deste provider não muda.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState.unauthenticated();

  /// Usado apenas para exercitar o roteamento antes do P0.6 ligar auth real.
  void signInStub(Set<UserRole> roles) {
    state = AuthState.authenticated(roles: roles);
  }

  void signOut() {
    state = const AuthState.unauthenticated();
  }

  /// Alterna o contexto ativo (professor ↔ aluno) para quem tem os dois
  /// papéis — usado pelo seletor no app bar.
  void switchContext(ActiveContext context) {
    if (!state.isAuthenticated) return;
    state = state.copyWith(activeContext: context);
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
