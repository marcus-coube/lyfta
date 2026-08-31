import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/http/api_exception.dart';
import '../../../core/http/providers.dart';
import '../domain/workout_event.dart';

final workoutApiProvider = Provider<WorkoutApi>((ref) {
  return WorkoutApi(ref.watch(workoutApiClientProvider).dio);
});

/// As duas rotas do contrato offline que o aluno usa (P1.5): baixar o treino
/// do dia e drenar a fila de execução.
class WorkoutApi {
  WorkoutApi(this._dio);

  final Dio _dio;

  /// `GET /v1/me/today` — o payload inteiro, para ser cacheado como veio.
  /// O aluno é o `sub` do token: não existe parâmetro de aluno aqui.
  Future<Map<String, dynamic>> today() async {
    final response = await _send<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>('/v1/me/today'),
    );
    return response!;
  }

  /// `POST /v1/sync/workout-logs` — lote idempotente por `client_id`.
  Future<SyncResult> pushLogs(List<WorkoutEvent> events) async {
    final response = await _send<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        '/v1/sync/workout-logs',
        data: {'events': events.map((e) => e.toJson()).toList()},
      ),
    );
    return SyncResult.fromJson(response!);
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
