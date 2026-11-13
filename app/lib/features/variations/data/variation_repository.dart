import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/http/api_exception.dart';
import '../../../core/http/providers.dart';
import '../../../shared/domain/plan.dart';
import '../domain/variation_status.dart';

final variationRepositoryProvider = Provider<VariationRepository>((ref) {
  return VariationRepository(ref.watch(workoutApiClientProvider).dio);
});

/// Variações de série do tenant (`/v1/variations` no `workout`, ADR-019).
/// Conteúdo do tenant: owner e coach leem e escrevem; não há exclusão, só
/// arquivar.
class VariationRepository {
  VariationRepository(this._dio);

  final Dio _dio;

  Future<List<SetVariation>> list({
    String query = '',
    VariationStatus status = VariationStatus.active,
  }) =>
      _call(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/v1/variations',
          queryParameters: {
            if (query.trim().isNotEmpty) 'q': query.trim(),
            'status': status.code,
          },
        );
        return [
          for (final raw in response.data!['items'] as List<dynamic>? ?? [])
            SetVariation.fromJson(raw as Map<String, dynamic>),
        ];
      });

  Future<SetVariation> create({
    required String name,
    required String description,
  }) =>
      _call(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/v1/variations',
          data: {'name': name, 'description': description},
        );
        return SetVariation.fromJson(response.data!);
      });

  Future<SetVariation> update(
    String id, {
    required String name,
    required String description,
  }) =>
      _call(() async {
        final response = await _dio.put<Map<String, dynamic>>(
          '/v1/variations/$id',
          data: {'name': name, 'description': description},
        );
        return SetVariation.fromJson(response.data!);
      });

  Future<SetVariation> setArchived(String id, {required bool archived}) =>
      _call(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/v1/variations/$id/${archived ? 'archive' : 'unarchive'}',
        );
        return SetVariation.fromJson(response.data!);
      });

  /// Desembrulha o [ApiException] do `ErrorMappingInterceptor`.
  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      final error = e.error;
      if (error is ApiException) throw error;
      throw const ApiException.network();
    }
  }
}
