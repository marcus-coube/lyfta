import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/http/api_exception.dart';
import '../../../core/http/providers.dart';
import '../domain/checkin.dart';

final checkinRepositoryProvider = Provider<CheckinRepository>((ref) {
  return CheckinRepository(ref.watch(commsApiClientProvider).dio);
});

/// Repositório da avaliação de treino (P3.3/P3.5 §2/§3) sobre o `comms`.
class CheckinRepository {
  CheckinRepository(this._dio);

  final Dio _dio;

  /// `student_id` nunca vai no corpo — o servidor sempre usa a claim
  /// (`POST /v1/checkins`, mesmo critério do `/v1/sync/workout-logs` do
  /// workout). Idempotente por `session_client_id`: reenviar a mesma sessão
  /// devolve o check-in original, não sobrescreve (P3.3).
  Future<WorkoutCheckin> create(CheckinDraft draft) async {
    final json = await _send(
      () => _dio.post<Map<String, dynamic>>('/v1/checkins', data: draft.toJson()),
    );
    return WorkoutCheckin.fromJson(json!);
  }

  /// Fila do coach (`GET /v1/checkins?student_id=`, P3.3) — não revisados
  /// primeiro, depois cronológico (já vem ordenado do servidor).
  Future<CheckinPage> list({
    required String studentId,
    String? cursor,
    int? limit,
  }) async {
    final json = await _send(
      () => _dio.get<Map<String, dynamic>>(
        '/v1/checkins',
        queryParameters: {
          'student_id': studentId,
          if (cursor != null) 'cursor': cursor,
          if (limit != null) 'limit': limit,
        },
      ),
    );
    final items = (json!['items'] as List<dynamic>? ?? const [])
        .map((raw) => WorkoutCheckin.fromJson(raw as Map<String, dynamic>))
        .toList();
    final cursorOut = json['next_cursor'] as String?;
    return CheckinPage(
      items: items,
      nextCursor: (cursorOut ?? '').isEmpty ? null : cursorOut,
    );
  }

  Future<WorkoutCheckin> review(String id) async {
    final json = await _send(
      () => _dio.post<Map<String, dynamic>>('/v1/checkins/$id/review'),
    );
    return WorkoutCheckin.fromJson(json!);
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
