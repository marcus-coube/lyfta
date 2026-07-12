import 'package:dio/dio.dart';

import '../../../core/http/api_client.dart';
import '../../../core/http/api_exception.dart';
import 'auth_session.dart';

/// Repositório de autenticação sobre o `identity` (ADR-013: só HTTP, sem
/// import de código entre serviços). Cobre os endpoints do plano P0.6:
/// signup do tenant, login (com resolução de `multiple_tenants`), refresh,
/// logout, aceite de convite e recuperação de senha.
///
/// Todas as chamadas usam [skipAuth] porque são públicas ou porque o próprio
/// endpoint gerencia a sessão (refresh não deve tentar se autenticar com o
/// access token expirado que originou a chamada).
class AuthRepository {
  AuthRepository(this._dio);

  final Dio _dio;

  Future<AuthSession> signup({
    required String businessName,
    required String slug,
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await _post(
      '/v1/tenants',
      data: {
        'business_name': businessName,
        'slug': slug,
        'name': name,
        'email': email,
        'password': password,
      },
    );
    return AuthSession.fromJson(response!);
  }

  /// Faz login. Se o e-mail existir em mais de um tenant e [tenantId] não
  /// for informado, lança [ApiException] com `code: multiple_tenants` e
  /// `params.tenants` — a camada de apresentação mostra o bottom sheet e
  /// chama de novo com o `tenantId` escolhido.
  Future<AuthSession> login({
    required String email,
    required String password,
    String? tenantId,
  }) async {
    final response = await _post(
      '/v1/auth/login',
      data: {
        'email': email,
        'password': password,
        if (tenantId != null) 'tenant_id': tenantId,
      },
    );
    return AuthSession.fromJson(response!);
  }

  Future<AuthSession> refresh({
    required String refreshToken,
    required String tenantId,
  }) async {
    final response = await _post(
      '/v1/auth/refresh',
      data: {'refresh_token': refreshToken, 'tenant_id': tenantId},
    );
    return AuthSession.fromJson(response!);
  }

  Future<void> logout({
    required String refreshToken,
    required String tenantId,
  }) {
    return _post(
      '/v1/auth/logout',
      data: {'refresh_token': refreshToken, 'tenant_id': tenantId},
    );
  }

  Future<AuthSession> acceptInvite({
    required String token,
    required String password,
  }) async {
    final response = await _post(
      '/v1/invitations/accept',
      data: {'token': token, 'password': password},
    );
    return AuthSession.fromJson(response!);
  }

  /// Sempre responde com sucesso (o backend nunca vaza se o e-mail existe).
  Future<void> forgotPassword({required String email}) {
    return _post('/v1/auth/forgot-password', data: {'email': email});
  }

  Future<void> resetPassword({
    required String token,
    required String password,
  }) {
    return _post(
      '/v1/auth/reset-password',
      data: {'token': token, 'password': password},
    );
  }

  /// POST com [skipAuth] (endpoints públicos ou que gerenciam a própria
  /// sessão) que desembrulha o [ApiException] anexado pelo
  /// `ErrorMappingInterceptor` em [DioException.error] — sem isto, todo
  /// `catch (e) on ApiException` da camada de apresentação nunca casaria,
  /// porque o Dio sempre lança `DioException`, não a exceção original.
  Future<Map<String, dynamic>?> _post(String path, {required Map<String, dynamic> data}) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        path,
        data: data,
        options: Options(extra: {'skipAuth': true}),
      );
      return response.data;
    } on DioException catch (e) {
      if (e.error is ApiException) throw e.error!;
      rethrow;
    }
  }
}

/// Extrai as opções de tenant de um [ApiException] `multiple_tenants`
/// (`params.tenants: [{tenant_id, tenant_name}]`).
extension MultipleTenantsError on ApiException {
  List<TenantOption> get tenantOptions {
    final raw = params['tenants'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(TenantOption.fromJson)
        .toList();
  }
}
