import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/http/api_exception.dart';
import '../../../core/http/providers.dart';

final agendaApiProvider = Provider<AgendaApi>((ref) {
  return AgendaApi(ref.watch(workoutApiClientProvider).dio);
});

/// As duas leituras do `workout` que a agenda semanal do aluno precisa
/// (P4.1): a rotação (mesmo payload de `GET /v1/me/today`, P1.5) e as
/// sessões sincronizadas por período (`GET /v1/me/sessions`, endpoint novo
/// desta tarefa).
class AgendaApi {
  AgendaApi(this._dio);

  final Dio _dio;

  /// O payload inteiro de `/me/today` — a agenda só lê `status`, `day.id` e
  /// `rotation`, mas pedir menos exigiria um endpoint novo só para isso.
  Future<Map<String, dynamic>> today() async {
    final response = await _send<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>('/v1/me/today'),
    );
    return response!;
  }

  /// `GET /v1/me/sessions?from=&to=` — sessões com `started_at` dentro de
  /// `[from, to)`. As datas viajam em UTC (RFC3339): o servidor não sabe de
  /// fuso do aluno, só compara instantes.
  Future<List<Map<String, dynamic>>> sessions({
    required DateTime from,
    required DateTime to,
  }) async {
    final response = await _send<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        '/v1/me/sessions',
        queryParameters: {
          'from': from.toUtc().toIso8601String(),
          'to': to.toUtc().toIso8601String(),
        },
      ),
    );
    return (response!['items'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
  }

  Future<T?> _send<T>(Future<Response<T>> Function() request) async {
    try {
      final response = await request();
      return response.data;
    } on DioException catch (e) {
      final error = e.error;
      if (error is ApiException) throw error;
      throw const ApiException.network();
    }
  }
}
