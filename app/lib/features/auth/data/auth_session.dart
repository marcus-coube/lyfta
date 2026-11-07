import '../../../core/auth/auth_state.dart';

/// Sessão devolvida por qualquer endpoint que emite tokens (signup, login,
/// refresh, accept invite) — espelha `tokenResponse` do `identity`
/// (`backend/identity/internal/http/auth.go`).
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.tenantId,
    required this.userId,
    required this.roles,
    this.needsConsent = false,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      tenantId: json['tenant_id'] as String,
      userId: json['user_id'] as String,
      roles: (json['roles'] as List<dynamic>).map((r) => r.toString()).toSet(),
      needsConsent: json['needs_consent'] as bool? ?? false,
    );
  }

  final String accessToken;
  final String refreshToken;
  final String tenantId;
  final String userId;
  final Set<String> roles;

  /// O usuário ainda não consentiu na versão atual dos termos (ou numa
  /// finalidade obrigatória do papel dele) — o app mostra a tela de
  /// consentimento antes de liberar o resto (ADR-008 §1, P4.5).
  final bool needsConsent;

  /// Papéis desta sessão no enum de UI (ver `userRolesFrom`).
  Set<UserRole> get userRoles => userRolesFrom(roles);
}

/// Uma opção de tenant devolvida pelo backend quando um e-mail existe em mais
/// de uma conta (`409 multiple_tenants` — ADR-002 §2c).
class TenantOption {
  const TenantOption({required this.tenantId, required this.tenantName});

  factory TenantOption.fromJson(Map<String, dynamic> json) {
    return TenantOption(
      tenantId: json['tenant_id'] as String,
      tenantName: json['tenant_name'] as String,
    );
  }

  final String tenantId;
  final String tenantName;
}
