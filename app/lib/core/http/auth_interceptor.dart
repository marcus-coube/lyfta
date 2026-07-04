import 'dart:async';

import 'package:dio/dio.dart';

import 'token_storage.dart';

/// Assinatura do refresh: recebe o refresh token atual e devolve o par novo,
/// ou lança se o refresh também falhar (sessão morta).
typedef RefreshTokens = Future<AuthTokens> Function(String refreshToken);

/// Callback disparado quando a sessão não pode mais ser renovada (refresh
/// falhou) — a camada de auth deve limpar o estado e redirecionar ao login.
typedef OnSessionExpired = void Function();

/// Interceptor Dio que:
/// 1. Injeta `Authorization: Bearer <access>` em toda requisição autenticada.
/// 2. Em `401`, tenta renovar a sessão via [refreshTokens] e reenvia a
///    requisição original — mas apenas **uma vez por token expirado**: se
///    várias requisições tomam 401 ao mesmo tempo, todas esperam o mesmo
///    refresh em andamento (fila), em vez de disparar N chamadas de refresh.
/// 3. Se o refresh falhar, propaga o erro original e chama [onSessionExpired].
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required Dio dio,
    required TokenStorage tokenStorage,
    required RefreshTokens refreshTokens,
    required OnSessionExpired onSessionExpired,
  })  : _dio = dio,
        _tokenStorage = tokenStorage,
        _refreshTokens = refreshTokens,
        _onSessionExpired = onSessionExpired;

  final Dio _dio;
  final TokenStorage _tokenStorage;
  final RefreshTokens _refreshTokens;
  final OnSessionExpired _onSessionExpired;

  /// Refresh em andamento (null quando nenhum está em curso). Requisições
  /// concorrentes que tomam 401 aguardam este mesmo future.
  Future<AuthTokens?>? _refreshing;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra['skipAuth'] != true) {
      final tokens = await _tokenStorage.read();
      if (tokens != null) {
        options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    final request = err.requestOptions;

    final isAuthEndpoint = request.extra['skipAuth'] == true;
    if (response?.statusCode != 401 || isAuthEndpoint) {
      handler.next(err);
      return;
    }

    // Já tentamos renovar nesta própria requisição — evita loop infinito.
    if (request.extra['retriedAfterRefresh'] == true) {
      handler.next(err);
      return;
    }

    final currentTokens = await _tokenStorage.read();
    if (currentTokens == null) {
      handler.next(err);
      return;
    }

    try {
      final newTokens = await _refreshOnce(currentTokens.refreshToken);
      if (newTokens == null) {
        _onSessionExpired();
        handler.next(err);
        return;
      }

      final retryOptions = request.copyWith(
        extra: {...request.extra, 'retriedAfterRefresh': true},
      );
      retryOptions.headers['Authorization'] = 'Bearer ${newTokens.accessToken}';

      final retryResponse = await _dio.fetch<dynamic>(retryOptions);
      handler.resolve(retryResponse);
    } catch (_) {
      _onSessionExpired();
      handler.next(err);
    }
  }

  /// Garante uma única chamada de refresh em voo mesmo com várias
  /// requisições concorrentes tomando 401 ao mesmo tempo.
  Future<AuthTokens?> _refreshOnce(String refreshToken) {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;

    final future = _doRefresh(refreshToken);
    _refreshing = future;
    return future.whenComplete(() => _refreshing = null);
  }

  Future<AuthTokens?> _doRefresh(String refreshToken) async {
    try {
      final newTokens = await _refreshTokens(refreshToken);
      await _tokenStorage.save(newTokens);
      return newTokens;
    } catch (_) {
      await _tokenStorage.clear();
      return null;
    }
  }
}
