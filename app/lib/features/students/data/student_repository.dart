import 'package:dio/dio.dart';

import '../../../core/http/api_exception.dart';
import '../domain/student.dart';

/// Repositório da lista de alunos sobre o serviço `identity` (P1.6).
class StudentRepository {
  StudentRepository(this._dio);

  final Dio _dio;

  Future<StudentPage> list({String query = '', String? cursor, int? limit}) async {
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
