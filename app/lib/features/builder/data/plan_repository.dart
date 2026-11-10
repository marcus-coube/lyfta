import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/http/api_exception.dart';
import '../../../core/http/providers.dart';
import '../../../shared/domain/plan.dart';

/// Repositório do builder sobre o cliente HTTP do `workout`.
final planRepositoryProvider = Provider<PlanRepository>((ref) {
  return PlanRepository(ref.watch(workoutApiClientProvider).dio);
});

/// Repositório do builder sobre o serviço `workout` (P1.4): criar plano,
/// salvar rascunho, publicar e listar os planos de um aluno.
class PlanRepository {
  PlanRepository(this._dio);

  final Dio _dio;

  /// Cria o plano em rascunho. A primeira versão só nasce quando a árvore é
  /// salva — plano recém-criado volta sem versão nenhuma.
  Future<Plan> create({
    required String studentId,
    required String title,
  }) async {
    final json = await _send<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        '/v1/plans',
        data: {'student_id': studentId, 'title': title},
      ),
    );
    return Plan.fromJson(json!);
  }

  /// Carrega o plano. Sem [version], vem o rascunho (se houver) e a última
  /// publicada caso contrário — que é o que a tela do professor abre.
  Future<Plan> byId(String id, {String? version}) async {
    final json = await _send<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        '/v1/plans/$id',
        queryParameters: {if (version != null) 'version': version},
      ),
    );
    return Plan.fromJson(json!);
  }

  /// Substitui a árvore inteira do rascunho. Se a última versão já estava
  /// publicada, o servidor abre uma nova — é assim que editar um plano
  /// publicado vira v2 sem tocar na v1 (ADR-004 §1).
  Future<Plan> saveDraft({
    required String planId,
    required String title,
    required List<WorkoutDay> days,
    String? description,
  }) async {
    final json = await _send<Map<String, dynamic>>(
      () => _dio.put<Map<String, dynamic>>(
        '/v1/plans/$planId/draft',
        data: {
          'title': title,
          if (description != null) 'description': description,
          'days': days.map((d) => d.toJson()).toList(),
        },
      ),
    );
    return Plan.fromJson(json!);
  }

  /// Publica o rascunho: congela a versão e passa a rotação do aluno para
  /// ela. Erros de negócio chegam como [ApiException] com `plan_incomplete`
  /// (com `reason`/`day_id`) ou `no_draft_to_publish`.
  Future<Plan> publish(String planId) async {
    final json = await _send<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>('/v1/plans/$planId/publish'),
    );
    return Plan.fromJson(json!);
  }

  /// Copia a versão mais recente para um plano novo em rascunho, fora da
  /// rotação (P6.2). Sem [studentId], fica com o mesmo aluno.
  Future<Plan> duplicate(String planId, {String? studentId}) async {
    final json = await _send<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        '/v1/plans/$planId/duplicate',
        data: {if (studentId != null) 'student_id': studentId},
      ),
    );
    return Plan.fromJson(json!);
  }

  /// Arquiva um plano que não está em uso (o ativo dá 409 `plan_is_active`).
  Future<void> archive(String planId) => _send<Map<String, dynamic>>(
        () => _dio.post<Map<String, dynamic>>('/v1/plans/$planId/archive'),
      );

  /// Faz deste o plano em uso do aluno (a rotação recomeça no 1º dia). É o
  /// único caminho de volta de um plano arquivado.
  Future<void> activate({
    required String studentId,
    required String planId,
  }) =>
      _send<Map<String, dynamic>>(
        () => _dio.post<Map<String, dynamic>>(
          '/v1/students/$studentId/plans/$planId/activate',
        ),
      );

  /// Copia a versão mais recente para um modelo novo, em rascunho (P6.1).
  Future<Plan> saveAsTemplate(String planId, {required String title}) async {
    final json = await _send<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        '/v1/plans/$planId/save-as-template',
        data: {'title': title},
      ),
    );
    return Plan.fromJson(json!);
  }

  Future<List<PlanSummary>> byStudent(String studentId) async {
    final json = await _send<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>('/v1/students/$studentId/plans'),
    );
    return (json!['items'] as List<dynamic>? ?? const [])
        .map((raw) => PlanSummary.fromJson(raw as Map<String, dynamic>))
        .toList();
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
