import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../http/api_exception.dart';
import '../http/providers.dart';

final pushRepositoryProvider = Provider<PushRepository>((ref) {
  return PushRepository(ref.watch(commsApiClientProvider).dio);
});

/// `POST /v1/devices` (P3.4, passo 1) — upsert do token de push do device
/// autenticado. `platform`/`locale` seguem o vocabulário do `comms`
/// (`domain.DevicePlatform`/`domain.IsValidLocale`).
class PushRepository {
  PushRepository(this._dio);

  final Dio _dio;

  Future<void> registerDevice({
    required String platform,
    required String token,
    required String locale,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/v1/devices',
        data: {'platform': platform, 'token': token, 'locale': locale},
      );
    } on DioException catch (e) {
      final error = e.error;
      if (error is ApiException) throw error;
      throw const ApiException.network();
    }
  }
}
