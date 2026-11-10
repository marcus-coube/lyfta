import 'package:dio/dio.dart';

import '../../../core/http/api_exception.dart';
import '../domain/student_overview.dart';

/// Resumo em lote do `workout` (último treino + plano ativo), uma chamada por
/// página da lista de alunos.
class StudentOverviewRepository {
  StudentOverviewRepository(this._dio);

  /// Teto de ids por chamada no servidor (`POST /v1/students/overview`).
  static const int maxIds = 100;

  final Dio _dio;

  /// Resumo por id de aluno. Quem o servidor não devolve (fora do vínculo)
  /// não aparece no mapa.
  Future<Map<String, StudentOverview>> overview(List<String> studentIds) async {
    if (studentIds.isEmpty) return const {};
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/students/overview',
        data: {'student_ids': studentIds},
      );
      final items = response.data!['items'] as List<dynamic>? ?? const [];
      return {
        for (final raw in items)
          (raw as Map<String, dynamic>)['student_id'] as String:
              StudentOverview.fromJson(raw),
      };
    } on DioException catch (e) {
      final error = e.error;
      if (error is ApiException) throw error;
      throw const ApiException.network();
    }
  }
}
