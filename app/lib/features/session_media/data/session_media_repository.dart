import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/http/api_exception.dart';
import '../../../core/http/providers.dart';
import '../domain/session_media.dart';

final sessionMediaRepositoryProvider = Provider<SessionMediaRepository>((ref) {
  return SessionMediaRepository(ref.watch(commsApiClientProvider).dio);
});

/// Mídia de execução do aluno sobre o `comms` (ADR-020, P12.1). Mesmo
/// presign em duas etapas do chat e das fotos de progresso: os bytes vão
/// direto ao storage, nunca pela API.
class SessionMediaRepository {
  SessionMediaRepository(this._dio);

  final Dio _dio;

  Future<List<SessionMedia>> list(String sessionClientId) async {
    final json = await _send(
      () => _dio.get<Map<String, dynamic>>(
        '/v1/me/session-media',
        queryParameters: {'session_client_id': sessionClientId},
      ),
    );
    return (json?['items'] as List<dynamic>? ?? const [])
        .map((raw) => SessionMedia.fromJson(raw as Map<String, dynamic>))
        .toList();
  }

  /// Lado do professor (P12.3): `GET /v1/session-media?student_id=&pending=`,
  /// mais recentes primeiro, com cursor. `media_url` vem assinada e curta.
  Future<SessionMediaPage> listForCoach({
    required String studentId,
    bool pendingOnly = false,
    String? cursor,
    int? limit,
  }) async {
    final json = await _send(
      () => _dio.get<Map<String, dynamic>>(
        '/v1/session-media',
        queryParameters: {
          'student_id': studentId,
          if (pendingOnly) 'pending': 'true',
          if (cursor != null) 'cursor': cursor,
          if (limit != null) 'limit': limit,
        },
      ),
    );
    final next = json?['next_cursor'] as String?;
    return SessionMediaPage(
      items: (json?['items'] as List<dynamic>? ?? const [])
          .map((raw) => SessionMedia.fromJson(raw as Map<String, dynamic>))
          .toList(),
      nextCursor: (next ?? '').isEmpty ? null : next,
    );
  }

  /// Ciência do professor; idempotente. Com [feedback], o servidor também
  /// manda a resposta ao chat do aluno (D7).
  Future<SessionMedia> ack(String id, {String? feedback}) async {
    final text = feedback?.trim() ?? '';
    final json = await _send(
      () => _dio.post<Map<String, dynamic>>(
        '/v1/session-media/$id/ack',
        data: {if (text.isNotEmpty) 'feedback': text},
      ),
    );
    return SessionMedia.fromJson(json!);
  }

  /// Presign → PUT com progresso → registro. Cancelar o [cancelToken] aborta o
  /// PUT (a exceção de cancelamento sobe como `DioException`).
  Future<SessionMedia> upload({
    required String sessionClientId,
    required PreparedMedia media,
    String? exerciseId,
    String? exerciseName,
    String? note,
    CancelToken? cancelToken,
    void Function(double progress)? onProgress,
  }) async {
    final presign = await _send(
      () => _dio.post<Map<String, dynamic>>(
        '/v1/me/session-media/presign',
        data: {
          'session_client_id': sessionClientId,
          'content_type': media.contentType,
          'size_bytes': media.sizeBytes,
        },
        cancelToken: cancelToken,
      ),
    );
    final headers = (presign!['required_headers'] as Map<String, dynamic>? ??
            const {})
        .map((k, v) => MapEntry(k, v.toString()));

    try {
      // `Dio` limpo, sem `baseUrl` nem interceptors de sessão (mesmo padrão
      // do chat e das fotos de progresso).
      await Dio().putUri<void>(
        Uri.parse(presign['upload_url'] as String),
        data: Stream<List<int>>.fromIterable([media.bytes]),
        cancelToken: cancelToken,
        onSendProgress: (sent, total) {
          if (total > 0) onProgress?.call(sent / total);
        },
        options: Options(
          headers: {
            ...headers,
            Headers.contentLengthHeader: media.sizeBytes,
          },
        ),
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw const ApiException.network();
    }

    final json = await _send(
      () => _dio.post<Map<String, dynamic>>(
        '/v1/me/session-media',
        data: {
          'session_client_id': sessionClientId,
          'media_key': presign['key'],
          if (exerciseId != null) 'exercise_id': exerciseId,
          if (exerciseName != null && exerciseName.isNotEmpty)
            'exercise_name': exerciseName,
          if (note != null && note.isNotEmpty) 'note': note,
        },
        cancelToken: cancelToken,
      ),
    );
    return SessionMedia.fromJson(json!);
  }

  Future<void> delete(String id) async {
    await _send(() => _dio.delete<void>('/v1/me/session-media/$id'));
  }

  /// Desembrulha o [ApiException] do `ErrorMappingInterceptor`; cancelamento
  /// passa intacto.
  Future<T?> _send<T>(Future<Response<T>> Function() request) async {
    try {
      return (await request()).data;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      final error = e.error;
      if (error is ApiException) throw error;
      throw const ApiException.network();
    }
  }
}
