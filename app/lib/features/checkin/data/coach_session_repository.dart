import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/http/api_exception.dart';
import '../../../core/http/providers.dart';
import '../domain/coach_session.dart';

final coachSessionRepositoryProvider = Provider<CoachSessionRepository>((ref) {
  return CoachSessionRepository(ref.watch(workoutApiClientProvider).dio);
});

/// Sessões do aluno lidas pelo professor no `workout` (P11.1). O app compõe
/// com os check-ins do `comms` — nenhum serviço chama o outro (ADR-013).
class CoachSessionRepository {
  CoachSessionRepository(this._dio);

  /// Teto de ids por chamada no servidor.
  static const int maxIds = 50;

  final Dio _dio;

  /// Resumo por `client_id`; sessão que ainda não chegou ao servidor (fila
  /// offline do aluno) não vem no mapa.
  Future<Map<String, CoachSession>> lookup(
    String studentId,
    List<String> clientIds,
  ) async {
    if (clientIds.isEmpty) return const {};
    final json = await _send(
      () => _dio.post<Map<String, dynamic>>(
        '/v1/students/$studentId/sessions/lookup',
        data: {'client_ids': clientIds},
      ),
    );
    return {
      for (final raw in json['items'] as List<dynamic>? ?? const [])
        (raw as Map<String, dynamic>)['client_id'] as String:
            CoachSession.fromJson(raw),
    };
  }

  Future<CoachSessionDetail> detail(String studentId, String clientId) async {
    final json = await _send(
      () => _dio.get<Map<String, dynamic>>(
        '/v1/students/$studentId/sessions/$clientId',
      ),
    );
    return CoachSessionDetail.fromJson(json);
  }

  Future<Map<String, dynamic>> _send(
    Future<Response<Map<String, dynamic>>> Function() request,
  ) async {
    try {
      return (await request()).data!;
    } on DioException catch (e) {
      final error = e.error;
      if (error is ApiException) throw error;
      throw const ApiException.network();
    }
  }
}
