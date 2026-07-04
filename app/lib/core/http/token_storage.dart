import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Par de tokens JWT (access curto + refresh longo) emitido pelo `identity`.
class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}

/// Persistência dos tokens de sessão.
///
/// Mobile/desktop: `flutter_secure_storage` (keychain/keystore). Web: cai no
/// backend padrão do plugin (`window.localStorage`) — aceitável para o MVP;
/// o tradeoff (XSS pode ler localStorage) é documentado aqui e revisitado
/// quando o produto exigir mais rigor em P0.6 (ligação real de auth).
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _accessKey = 'lyfta.access_token';
  static const _refreshKey = 'lyfta.refresh_token';

  final FlutterSecureStorage _storage;

  Future<AuthTokens?> read() async {
    final access = await _storage.read(key: _accessKey);
    final refresh = await _storage.read(key: _refreshKey);
    if (access == null || refresh == null) return null;
    return AuthTokens(accessToken: access, refreshToken: refresh);
  }

  Future<void> save(AuthTokens tokens) async {
    await _storage.write(key: _accessKey, value: tokens.accessToken);
    await _storage.write(key: _refreshKey, value: tokens.refreshToken);
  }

  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}
