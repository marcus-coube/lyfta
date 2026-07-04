/// Papel do usuário na sessão atual — usado para escolher o shell (professor
/// × aluno) e, quando o usuário acumula os dois papéis, alternar contexto via
/// seletor no app bar.
enum UserRole { coach, student }

/// Contexto ativo escolhido pelo usuário (relevante só quando ele tem os dois
/// papéis simultaneamente, ex.: dono de estúdio que também treina).
enum ActiveContext { coach, student }

/// Estado de autenticação usado pelo `go_router` para decidir redirect.
///
/// Esta é uma modelagem **stub**: reflete só o necessário para roteamento
/// (autenticado? qual(is) papel(is)? contexto ativo?). P0.6 substitui a
/// origem dos dados por sessão real vinda do `identity`, sem mudar este
/// contrato de estado.
class AuthState {
  const AuthState({
    required this.status,
    this.roles = const {},
    this.activeContext,
  });

  const AuthState.unknown() : this(status: AuthStatus.unknown);
  const AuthState.unauthenticated() : this(status: AuthStatus.unauthenticated);

  factory AuthState.authenticated({
    required Set<UserRole> roles,
    ActiveContext? activeContext,
  }) {
    final resolvedContext = activeContext ??
        (roles.contains(UserRole.coach)
            ? ActiveContext.coach
            : ActiveContext.student);
    return AuthState(
      status: AuthStatus.authenticated,
      roles: roles,
      activeContext: resolvedContext,
    );
  }

  final AuthStatus status;
  final Set<UserRole> roles;
  final ActiveContext? activeContext;

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get hasBothRoles =>
      roles.contains(UserRole.coach) && roles.contains(UserRole.student);

  AuthState copyWith({ActiveContext? activeContext}) {
    return AuthState(
      status: status,
      roles: roles,
      activeContext: activeContext ?? this.activeContext,
    );
  }
}

enum AuthStatus {
  /// Ainda não sabemos se há sessão válida (ex.: lendo secure storage).
  unknown,
  unauthenticated,
  authenticated,
}
