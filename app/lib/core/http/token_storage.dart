import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Par de tokens JWT (access curto + refresh longo) emitido pelo `identity`.
class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}

/// Sessão completa persistida entre restarts do app: os tokens mais os
/// metadados devolvidos junto (`tenant_id`, `user_id`, `roles` —
/// `tokenResponse` em `backend/identity/internal/http/auth.go`). Guardar
/// esses metadados evita decodificar o JWT no cliente só para saber o
/// tenant/papéis no boot.
class StoredSession {
  const StoredSession({
    required this.tokens,
    required this.tenantId,
    required this.userId,
    required this.roles,
  });

  final AuthTokens tokens;
  final String tenantId;
  final String userId;
  final Set<String> roles;
}

/// Persistência dos tokens de sessão.
///
/// Mobile/desktop: `flutter_secure_storage` (keychain/keystore). Web: cai no
/// backend padrão do plugin (`window.localStorage`) — **tradeoff aceito para
/// o MVP**: localStorage é acessível por qualquer script no mesmo
/// origin, então um XSS na app web poderia ler o refresh token. Mitigado
/// por: (a) access token de vida curta (15min — `security.AccessTokenTTL`
/// no backend), (b) CSP e sanitização de input ficam como dívida a
/// endereçar antes de dados sensíveis de aluno trafegarem por aqui, (c)
/// nenhum dado do treino em si fica em localStorage, só os tokens. Revisitar
/// com `flutter_secure_storage` web (IndexedDB + WebCrypto) se o rigor
/// exigido aumentar.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _accessKey = 'lyfta.access_token';
  static const _refreshKey = 'lyfta.refresh_token';
  static const _tenantIdKey = 'lyfta.tenant_id';
  static const _userIdKey = 'lyfta.user_id';
  static const _rolesKey = 'lyfta.roles';

  final FlutterSecureStorage _storage;

  Future<AuthTokens?> read() async {
    final access = await _storage.read(key: _accessKey);
    final refresh = await _storage.read(key: _refreshKey);
    if (access == null || refresh == null) return null;
    return AuthTokens(accessToken: access, refreshToken: refresh);
  }

  /// Lê a sessão completa (tokens + metadados) — usada no boot do app para
  /// restaurar `AuthState` sem precisar de round-trip ao backend.
  Future<StoredSession?> readSession() async {
    final tokens = await read();
    final tenantId = await _storage.read(key: _tenantIdKey);
    final userId = await _storage.read(key: _userIdKey);
    final rolesRaw = await _storage.read(key: _rolesKey);
    if (tokens == null || tenantId == null || userId == null || rolesRaw == null) {
      return null;
    }
    return StoredSession(
      tokens: tokens,
      tenantId: tenantId,
      userId: userId,
      roles: rolesRaw.isEmpty ? {} : rolesRaw.split(',').toSet(),
    );
  }

  Future<void> save(AuthTokens tokens) async {
    await _storage.write(key: _accessKey, value: tokens.accessToken);
    await _storage.write(key: _refreshKey, value: tokens.refreshToken);
  }

  /// Salva a sessão completa (tokens + metadados) — usado após
  /// signup/login/refresh/accept invite.
  Future<void> saveSession(StoredSession session) async {
    await save(session.tokens);
    await _storage.write(key: _tenantIdKey, value: session.tenantId);
    await _storage.write(key: _userIdKey, value: session.userId);
    await _storage.write(key: _rolesKey, value: session.roles.join(','));
  }

  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _tenantIdKey);
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _rolesKey);
  }
}
