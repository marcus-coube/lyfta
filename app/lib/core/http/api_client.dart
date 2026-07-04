import 'package:dio/dio.dart';

import 'auth_interceptor.dart';
import 'error_mapping_interceptor.dart';
import 'token_storage.dart';

/// Fábrica de instâncias [Dio] já equipadas com os interceptors do core:
/// autenticação (Bearer + refresh) e mapeamento de erro (code+params).
///
/// Um `ApiClient` por serviço (identity/workout/assessment/comms — ADR-013),
/// todos compartilhando o mesmo [TokenStorage] e política de refresh (o
/// refresh token sempre é emitido pelo `identity`).
class ApiClient {
  ApiClient({
    required String baseUrl,
    required TokenStorage tokenStorage,
    required RefreshTokens refreshTokens,
    required OnSessionExpired onSessionExpired,
  }) : dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
          ),
        ) {
    dio.interceptors.addAll([
      AuthInterceptor(
        dio: dio,
        tokenStorage: tokenStorage,
        refreshTokens: refreshTokens,
        onSessionExpired: onSessionExpired,
      ),
      ErrorMappingInterceptor(),
    ]);
  }

  final Dio dio;
}

/// Marca uma requisição para não receber `Authorization` nem passar pelo
/// fluxo de refresh (ex.: login, signup, refresh em si).
RequestOptions skipAuth(RequestOptions options) {
  options.extra['skipAuth'] = true;
  return options;
}
