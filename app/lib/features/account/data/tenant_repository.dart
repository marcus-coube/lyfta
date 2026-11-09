import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/http/api_exception.dart';
import '../../../core/http/providers.dart';

/// Configurações da organização (`GET/PUT /v1/tenant`, P5.1).
class TenantSettings {
  const TenantSettings({
    required this.id,
    required this.name,
    required this.slug,
    required this.locale,
    required this.timezone,
    required this.coachBillingAccess,
  });

  factory TenantSettings.fromJson(Map<String, dynamic> json) {
    return TenantSettings(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      locale: json['locale'] as String,
      timezone: json['timezone'] as String,
      coachBillingAccess: json['coach_billing_access'] as String,
    );
  }

  final String id;
  final String name;
  final String slug;
  final String locale;

  /// Nome IANA (ADR-007 §3).
  final String timezone;

  /// `status_only` | `own_students` (ADR-017 §3); a tela que o controla é a
  /// do financeiro (P7.4).
  final String coachBillingAccess;
}

/// Organização sobre o `identity`.
class TenantRepository {
  TenantRepository(this._dio);

  final Dio _dio;

  Future<TenantSettings> get() => _call(() async {
        final response = await _dio.get<Map<String, dynamic>>('/v1/tenant');
        return TenantSettings.fromJson(response.data!);
      });

  /// Só owner. Campo nulo não é enviado e o servidor mantém o valor atual.
  /// Fuso inválido vira `invalid_timezone` (422).
  Future<TenantSettings> update({String? name, String? timezone}) =>
      _call(() async {
        final response = await _dio.put<Map<String, dynamic>>(
          '/v1/tenant',
          data: {
            if (name != null) 'name': name,
            if (timezone != null) 'timezone': timezone,
          },
        );
        return TenantSettings.fromJson(response.data!);
      });

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      final error = e.error;
      if (error is ApiException) throw error;
      throw const ApiException.network();
    }
  }
}

final tenantRepositoryProvider = Provider<TenantRepository>((ref) {
  return TenantRepository(ref.watch(identityApiClientProvider).dio);
});

/// Organização do usuário logado.
final tenantSettingsProvider =
    FutureProvider.autoDispose<TenantSettings>((ref) {
  return ref.watch(tenantRepositoryProvider).get();
});
