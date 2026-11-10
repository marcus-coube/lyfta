import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/http/api_exception.dart';
import '../../../core/http/providers.dart';
import '../../../shared/domain/plan.dart';
import '../domain/template.dart';

final templateRepositoryProvider = Provider<TemplateRepository>((ref) {
  return TemplateRepository(ref.watch(workoutApiClientProvider).dio);
});

/// Modelos de treino sobre o `workout` (P6.1, ADR-018). Ler/editar/publicar a
/// árvore do modelo reusa as rotas de plano (`PlanRepository`).
class TemplateRepository {
  TemplateRepository(this._dio);

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

  /// [status]: vazio = ativos; `archived` e `all` ampliam.
  Future<TemplatePage> list({
    String query = '',
    String status = '',
    String? cursor,
    int? limit,
  }) =>
      _call(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/v1/templates',
          queryParameters: {
            if (query.trim().isNotEmpty) 'q': query.trim(),
            if (status.isNotEmpty) 'status': status,
            if (cursor != null) 'cursor': cursor,
            if (limit != null) 'limit': limit,
          },
        );
        final data = response.data!;
        return TemplatePage(
          items: (data['items'] as List<dynamic>? ?? const [])
              .map(
                (raw) => TemplateSummary.fromJson(raw as Map<String, dynamic>),
              )
              .toList(),
          nextCursor: data['next_cursor'] as String?,
        );
      });

  /// Cria o modelo em rascunho; a árvore entra pelo builder.
  Future<Plan> create({required String title, String description = ''}) =>
      _call(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/v1/templates',
          data: {'title': title, 'description': description},
        );
        return Plan.fromJson(response.data!);
      });

  Future<void> archive(String id) => _call(
        () => _dio.post<Map<String, dynamic>>('/v1/templates/$id/archive'),
      );

  Future<void> unarchive(String id) => _call(
        () => _dio.post<Map<String, dynamic>>('/v1/templates/$id/unarchive'),
      );

  /// Cópia da última versão publicada para cada aluno. Com [publish] o plano
  /// entra direto na rotação; sem, nasce como rascunho.
  Future<List<BatchItem>> assign(
    String id, {
    required List<String> studentIds,
    required bool publish,
  }) =>
      _call(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/v1/templates/$id/assign',
          data: {'student_ids': studentIds, 'publish': publish},
        );
        return _items(response.data!);
      });

  Future<TemplateRecipients> recipients(String id) => _call(() async {
        final response = await _dio
            .get<Map<String, dynamic>>('/v1/templates/$id/recipients');
        final data = response.data!;
        return TemplateRecipients(
          templateVersionNo: data['template_version_no'] as int? ?? 0,
          items: (data['items'] as List<dynamic>? ?? const [])
              .map(
                (raw) =>
                    TemplateRecipient.fromJson(raw as Map<String, dynamic>),
              )
              .toList(),
        );
      });

  /// Troca a árvore dos planos escolhidos pela última versão publicada do
  /// modelo e publica versão nova em cada um.
  Future<List<BatchItem>> reapply(
    String id, {
    required List<String> planIds,
  }) =>
      _call(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/v1/templates/$id/reapply',
          data: {'plan_ids': planIds},
        );
        return _items(response.data!);
      });

  List<BatchItem> _items(Map<String, dynamic> data) =>
      (data['items'] as List<dynamic>? ?? const [])
          .map((raw) => BatchItem.fromJson(raw as Map<String, dynamic>))
          .toList();
}
