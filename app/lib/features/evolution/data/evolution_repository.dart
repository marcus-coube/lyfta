import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/http/api_exception.dart';
import '../../../core/http/providers.dart';
import '../domain/bioimpedance.dart';
import '../domain/evolution_scope.dart';
import '../domain/evolution_summary.dart';
import '../domain/exercise_history.dart';
import '../domain/measurement.dart';
import '../domain/progress_photo.dart';

/// Uma página de qualquer uma das três listagens do `assessment`
/// (medidas/bioimpedância/fotos) — cursor keyset por `measured_at|taken_at`
/// desc (P2.3), mesmo formato opaco da biblioteca do `workout`.
class EvolutionPage<T> {
  const EvolutionPage({required this.items, this.nextCursor});

  final List<T> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

final evolutionRepositoryProvider = Provider<EvolutionRepository>((ref) {
  return EvolutionRepository(
    workoutDio: ref.watch(workoutApiClientProvider).dio,
    assessmentDio: ref.watch(assessmentApiClientProvider).dio,
  );
});

/// Repositório da tela Evolução: histórico de carga sobre o `workout`
/// (P2.1) e medidas/bioimpedância/fotos/resumo sobre o `assessment` (P2.3)
/// — dois serviços, dois `Dio` (ADR-013: só HTTP entre eles, nenhum import
/// de código).
///
/// Todo método recebe um [EvolutionScope]: `EvolutionScope.me()` para a tela
/// do aluno (P2.4, rotas `/me/...`) ou `EvolutionScope.student(id)` para a
/// ficha do coach (P2.5, rotas `/students/{id}/...`). As duas portas de cada
/// endpoint têm o mesmo formato nos dois serviços, então [EvolutionScope]
/// resolve o prefixo uma vez só — nenhum controller/widget precisa saber
/// qual porta está usando.
class EvolutionRepository {
  EvolutionRepository({required Dio workoutDio, required Dio assessmentDio})
      : _workout = workoutDio,
        _assessment = assessmentDio;

  final Dio _workout;
  final Dio _assessment;

  // ---------------------------------------------------------------------
  // Carga (workout, P2.1)
  // ---------------------------------------------------------------------

  /// Índice de exercícios já treinados — alimenta o seletor da aba Carga.
  Future<List<LoggedExercise>> loggedExercises(EvolutionScope scope) async {
    final json = await _get<Map<String, dynamic>>(
      _workout,
      '${scope.basePath}/exercises/logged',
    );
    final items = (json!['items'] as List<dynamic>? ?? const [])
        .map((raw) => LoggedExercise.fromJson(raw as Map<String, dynamic>))
        .toList();
    return items;
  }

  /// Histórico de um exercício, mais antigo que `since` (ou tudo, se
  /// `since` for nulo) — em ordem decrescente, igual ao servidor devolve.
  ///
  /// O endpoint não tem `?since=` (nota de execução do P2.1): o range da
  /// tela se resolve paginando pelo cursor até passar da data de corte. Um
  /// teto de páginas evita paginar para sempre num histórico gigantesco —
  /// se algum dia isso morder de verdade, o parâmetro entra no servidor.
  Future<List<ExerciseHistoryPoint>> exerciseHistory(
    EvolutionScope scope,
    String exerciseId, {
    DateTime? since,
  }) async {
    const pageLimit = 60;
    const maxPages = 40;
    final points = <ExerciseHistoryPoint>[];
    String? cursor;

    for (var page = 0; page < maxPages; page++) {
      final json = await _get<Map<String, dynamic>>(
        _workout,
        '${scope.basePath}/exercises/$exerciseId/history',
        query: {
          'limit': pageLimit,
          if (cursor != null) 'cursor': cursor,
        },
      );
      final result = ExerciseHistoryPage.fromJson(json!);
      points.addAll(result.items);

      final oldest =
          result.items.isEmpty ? null : result.items.last.performedAt;
      final pastCutoff =
          since != null && oldest != null && oldest.isBefore(since);
      if (!result.hasMore || pastCutoff) break;
      cursor = result.nextCursor;
    }

    if (since == null) return points;
    return points.where((p) => !p.performedAt.isBefore(since)).toList();
  }

  // ---------------------------------------------------------------------
  // Medidas corporais (assessment, P2.3)
  // ---------------------------------------------------------------------

  Future<EvolutionPage<BodyMeasurement>> listMeasurements(
    EvolutionScope scope, {
    String? cursor,
    int? limit,
  }) async {
    final json = await _get<Map<String, dynamic>>(
      _assessment,
      '${scope.basePath}/measurements',
      query: {
        if (cursor != null) 'cursor': cursor,
        if (limit != null) 'limit': limit,
      },
    );
    return _page(json!, BodyMeasurement.fromJson);
  }

  Future<BodyMeasurement> createMeasurement(
    EvolutionScope scope,
    MeasurementDraft draft,
  ) async {
    final json = await _send(
      () => _assessment.post<Map<String, dynamic>>(
        '${scope.basePath}/measurements',
        data: draft.toJson(),
      ),
    );
    return BodyMeasurement.fromJson(json!);
  }

  Future<void> deleteMeasurement(EvolutionScope scope, String id) async {
    await _send(
      () => _assessment.delete<void>('${scope.basePath}/measurements/$id'),
    );
  }

  // ---------------------------------------------------------------------
  // Bioimpedância (assessment, P2.3)
  // ---------------------------------------------------------------------

  Future<EvolutionPage<BioimpedanceRecord>> listBioimpedance(
    EvolutionScope scope, {
    String? cursor,
    int? limit,
  }) async {
    final json = await _get<Map<String, dynamic>>(
      _assessment,
      '${scope.basePath}/bioimpedance',
      query: {
        if (cursor != null) 'cursor': cursor,
        if (limit != null) 'limit': limit,
      },
    );
    return _page(json!, BioimpedanceRecord.fromJson);
  }

  Future<BioimpedanceRecord> createBioimpedance(
    EvolutionScope scope,
    BioimpedanceDraft draft,
  ) async {
    final json = await _send(
      () => _assessment.post<Map<String, dynamic>>(
        '${scope.basePath}/bioimpedance',
        data: draft.toJson(),
      ),
    );
    return BioimpedanceRecord.fromJson(json!);
  }

  Future<void> deleteBioimpedance(EvolutionScope scope, String id) async {
    await _send(
      () => _assessment.delete<void>('${scope.basePath}/bioimpedance/$id'),
    );
  }

  // ---------------------------------------------------------------------
  // Fotos de evolução (assessment, P2.3)
  // ---------------------------------------------------------------------

  Future<EvolutionPage<ProgressPhoto>> listPhotos(
    EvolutionScope scope, {
    String? cursor,
    int? limit,
  }) async {
    final json = await _get<Map<String, dynamic>>(
      _assessment,
      '${scope.basePath}/photos',
      query: {
        if (cursor != null) 'cursor': cursor,
        if (limit != null) 'limit': limit,
      },
    );
    return _page(json!, ProgressPhoto.fromJson);
  }

  /// Pede a URL assinada para o upload (etapa 1 das duas do presign,
  /// P1.2/P2.3): o serviço nunca recebe os bytes da foto.
  Future<AssessmentUploadTarget> presignPhoto(
    EvolutionScope scope, {
    required String contentType,
    required int sizeBytes,
  }) async {
    final json = await _send(
      () => _assessment.post<Map<String, dynamic>>(
        '${scope.basePath}/media/presign',
        data: {'content_type': contentType, 'size_bytes': sizeBytes},
      ),
    );
    return AssessmentUploadTarget.fromJson(json!);
  }

  /// Etapa 2: PUT direto no storage, fora da API (mesmo padrão do upload de
  /// mídia de exercício, P1.2) — um `Dio` limpo, sem `baseUrl` nem os
  /// interceptors de sessão.
  Future<void> uploadPhotoBytes(
    AssessmentUploadTarget target,
    Uint8List bytes,
  ) async {
    await Dio().putUri<void>(
      Uri.parse(target.uploadUrl),
      data: Stream<List<int>>.fromIterable([bytes]),
      options: Options(
        headers: {
          ...target.headers,
          Headers.contentLengthHeader: bytes.length,
        },
      ),
    );
  }

  /// Cadastra a foto depois do upload — `mediaKey` é sempre a `key`
  /// devolvida pelo presign, nunca inventada no cliente (o servidor confere
  /// que ela cai na pasta do aluno certo).
  Future<ProgressPhoto> createPhoto(
    EvolutionScope scope, {
    required DateTime takenAt,
    required Pose pose,
    required String mediaKey,
    String notes = '',
  }) async {
    final json = await _send(
      () => _assessment.post<Map<String, dynamic>>(
        '${scope.basePath}/photos',
        data: {
          'taken_at': takenAt.toIso8601String().substring(0, 10),
          'pose': pose.code,
          'media_key': mediaKey,
          'notes': notes,
        },
      ),
    );
    return ProgressPhoto.fromJson(json!);
  }

  Future<void> deletePhoto(EvolutionScope scope, String id) async {
    await _send(
      () => _assessment.delete<void>('${scope.basePath}/photos/$id'),
    );
  }

  // ---------------------------------------------------------------------
  // Resumo do coach (assessment, P2.3) — não existe porta `/me/summary`: só
  // o coach vê o condensado, a tela do aluno já tem as três listas.
  // ---------------------------------------------------------------------

  Future<EvolutionSummary> summary(EvolutionScope scope) async {
    assert(
      scope.isCoach,
      'resumo é só do coach — o assessment não expõe /me/summary',
    );
    final json =
        await _get<Map<String, dynamic>>(_assessment, '${scope.basePath}/summary');
    return EvolutionSummary.fromJson(json!);
  }

  // ---------------------------------------------------------------------

  EvolutionPage<T> _page<T>(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final items = (json['items'] as List<dynamic>? ?? const [])
        .map((raw) => fromJson(raw as Map<String, dynamic>))
        .toList();
    final cursor = json['next_cursor'] as String?;
    return EvolutionPage(
      items: items,
      nextCursor: (cursor ?? '').isEmpty ? null : cursor,
    );
  }

  Future<T?> _get<T>(Dio dio, String path, {Map<String, dynamic>? query}) {
    return _send<T>(() => dio.get<T>(path, queryParameters: query));
  }

  /// Desembrulha o [ApiException] que o `ErrorMappingInterceptor` anexa ao
  /// `DioException` — sem isso, `catch on ApiException` na apresentação
  /// nunca casaria.
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
