import 'package:dio/dio.dart';

import '../../../core/http/api_exception.dart';
import '../domain/student.dart';

/// Repositório da lista de alunos sobre o serviço `identity` (P1.6).
class StudentRepository {
  StudentRepository(this._dio);

  final Dio _dio;

  Future<StudentPage> list({
    String query = '',
    String? cursor,
    int? limit,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/v1/users',
        queryParameters: {
          'role': 'student',
          if (query.trim().isNotEmpty) 'q': query.trim(),
          if (cursor != null) 'cursor': cursor,
          if (limit != null) 'limit': limit,
        },
      );
      return StudentPage.fromJson(response.data!);
    } on DioException catch (e) {
      final error = e.error;
      if (error is ApiException) throw error;
      throw const ApiException.network();
    }
  }

  /// Professores que podem receber alunos: coaches e owners ativos, sem
  /// repetir quem tem os dois papéis.
  Future<List<CoachOption>> listCoaches() async {
    try {
      final byId = <String, CoachOption>{};
      for (final role in const ['owner', 'coach']) {
        final response = await _dio.get<Map<String, dynamic>>(
          '/v1/users',
          queryParameters: {'role': role, 'status': 'active', 'limit': 200},
        );
        for (final raw
            in response.data!['items'] as List<dynamic>? ?? const []) {
          final option = CoachOption.fromJson(raw as Map<String, dynamic>);
          byId[option.id] = option;
        }
      }
      return byId.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    } on DioException catch (e) {
      final error = e.error;
      if (error is ApiException) throw error;
      throw const ApiException.network();
    }
  }

  /// Troca o professor do aluno (`PUT /v1/students/{id}/coach`, só owner).
  Future<void> reassignCoach({
    required String studentId,
    required String coachId,
  }) async {
    try {
      await _dio.put<Map<String, dynamic>>(
        '/v1/students/$studentId/coach',
        data: {'coach_id': coachId},
      );
    } on DioException catch (e) {
      final error = e.error;
      if (error is ApiException) throw error;
      throw const ApiException.network();
    }
  }

  /// Convida um aluno novo. O nome é opcional na API, mas a tela sempre
  /// manda: sem ele a lista mostraria e-mails.
  Future<void> invite({required String email, required String name}) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/v1/invitations',
        data: {'email': email, 'role': 'student', 'name': name},
      );
    } on DioException catch (e) {
      final error = e.error;
      if (error is ApiException) throw error;
      throw const ApiException.network();
    }
  }
}
