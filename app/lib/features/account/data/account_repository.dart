import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/http/api_exception.dart';
import '../../../core/http/providers.dart';

/// Estado de consentimento do usuário (`GET /v1/me/consents`, ADR-008 §1).
class ConsentStatus {
  const ConsentStatus({
    required this.termsVersion,
    required this.required,
    required this.granted,
    required this.needsConsent,
    this.accessToken,
  });

  factory ConsentStatus.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? raw) =>
        (raw as List<dynamic>? ?? const []).map((e) => e.toString()).toList();
    return ConsentStatus(
      termsVersion: json['terms_version'] as String,
      required: strings(json['required']),
      granted: strings(json['granted']),
      needsConsent: json['needs_consent'] as bool? ?? false,
      accessToken: json['access_token'] as String?,
    );
  }

  final String termsVersion;
  final List<String> required;
  final List<String> granted;
  final bool needsConsent;

  /// Só vem no `PUT`: token novo com as finalidades atualizadas nas claims.
  final String? accessToken;

  bool has(String purpose) => granted.contains(purpose);
}

/// Finalidades de consentimento (mesmos valores do `identity`).
class ConsentPurpose {
  const ConsentPurpose._();

  static const terms = 'terms';
  static const healthData = 'health_data';
  static const progressPhotos = 'progress_photos';
}

/// Conta do próprio usuário sobre o `identity`: consentimentos (ADR-008 §1) e
/// exclusão de conta (ADR-008 §2) — P4.5.
class AccountRepository {
  AccountRepository(this._dio, {required this.termsVersion});

  final Dio _dio;
  final String termsVersion;

  Future<ConsentStatus> consents() => _call(() async {
        final response =
            await _dio.get<Map<String, dynamic>>('/v1/me/consents');
        return ConsentStatus.fromJson(response.data!);
      });

  /// Concede (`true`) ou revoga (`false`) finalidades. Devolve o estado novo
  /// com um access token já refletindo a mudança.
  Future<ConsentStatus> putConsents(Map<String, bool> consents) =>
      _call(() async {
        final response = await _dio.put<Map<String, dynamic>>(
          '/v1/me/consents',
          data: {'terms_version': termsVersion, 'consents': consents},
        );
        return ConsentStatus.fromJson(response.data!);
      });

  /// Exclui a conta, confirmada pela senha. Falha de serviço vira
  /// `erasure_failed` (502) e pode ser repetida.
  Future<void> deleteMe(String password) => _call(() async {
        await _dio.delete<void>('/v1/me', data: {'password': password});
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

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return AccountRepository(
    ref.watch(identityApiClientProvider).dio,
    termsVersion: AppConfig.termsVersion,
  );
});
