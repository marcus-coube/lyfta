import 'package:dio/dio.dart';

import '../../../core/http/api_exception.dart';
import '../domain/student.dart';

/// Repositório da lista de alunos sobre o serviço `identity` (P1.6).
class StudentRepository {
  StudentRepository(this._dio);

  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      final error = e.error;
      if (error is ApiException) throw error;
      throw const ApiException.network();
    }
  }

  /// Uma página de `GET /v1/students` (cursor do servidor, sem teto de
  /// alunos). `coachId` só vale para o owner; o coach sempre vê os seus.
  Future<StudentPage> list({
    String query = '',
    StudentStatusFilter status = StudentStatusFilter.active,
    String? coachId,
    String? cursor,
    int? limit,
  }) =>
      _call(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/v1/students',
          queryParameters: {
            'status': status.apiValue,
            if (query.trim().isNotEmpty) 'q': query.trim(),
            if (coachId != null) 'coach_id': coachId,
            if (cursor != null) 'cursor': cursor,
            if (limit != null) 'limit': limit,
          },
        );
        return StudentPage.fromJson(response.data!);
      });

  /// Ficha: cadastro, professor, status e convite pendente.
  Future<Student> get(String id) => _call(() async {
        final response =
            await _dio.get<Map<String, dynamic>>('/v1/students/$id');
        return Student.fromJson(response.data!);
      });

  /// Edita cadastro. `null` mantém o campo; `''` em telefone/nascimento apaga
  /// (contrato do `PATCH`). Nascimento vai como `yyyy-MM-dd`.
  Future<Student> update(
    String id, {
    String? name,
    String? phone,
    String? birthDate,
  }) =>
      _call(() async {
        final response = await _dio.patch<Map<String, dynamic>>(
          '/v1/students/$id',
          data: {
            if (name != null) 'name': name,
            if (phone != null) 'phone': phone,
            if (birthDate != null) 'birth_date': birthDate,
          },
        );
        return Student.fromJson(response.data!);
      });

  Future<void> deactivate(String id, {String? reason}) =>
      _changeStatus(id, 'deactivate', reason);

  Future<void> reactivate(String id, {String? reason}) =>
      _changeStatus(id, 'reactivate', reason);

  Future<void> _changeStatus(String id, String action, String? reason) =>
      _call(() async {
        await _dio.post<Map<String, dynamic>>(
          '/v1/students/$id/$action',
          data: {if ((reason ?? '').isNotEmpty) 'reason': reason},
        );
      });

  Future<List<StatusEvent>> statusHistory(String id) => _call(() async {
        final response = await _dio
            .get<Map<String, dynamic>>('/v1/students/$id/status-history');
        return (response.data!['items'] as List<dynamic>? ?? const [])
            .map((raw) => StatusEvent.fromJson(raw as Map<String, dynamic>))
            .toList();
      });

  Future<void> resendInvitation(String invitationId) => _call(() async {
        await _dio.post<Map<String, dynamic>>(
          '/v1/invitations/$invitationId/resend',
        );
      });

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
