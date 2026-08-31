import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/http/api_exception.dart';
import '../../../core/http/providers.dart';
import '../../../shared/domain/exercise.dart';

/// Repositório da biblioteca sobre o cliente HTTP do `workout`.
final exerciseRepositoryProvider = Provider<ExerciseRepository>((ref) {
  return ExerciseRepository(ref.watch(workoutApiClientProvider).dio);
});

/// Repositório da biblioteca de exercícios sobre o serviço `workout`
/// (ADR-013: só HTTP). Cobre os endpoints do P1.3 (listar, ler, criar,
/// editar) e o upload por URL presignada do P1.2.
class ExerciseRepository {
  ExerciseRepository(this._dio);

  final Dio _dio;

  /// Lista a biblioteca visível para o tenant (globais + próprios), já
  /// resolvida no idioma do usuário pelo backend.
  Future<ExercisePage> list({
    ExerciseFilter filter = const ExerciseFilter(),
    String? cursor,
    int? limit,
  }) async {
    final json = await _get<Map<String, dynamic>>(
      '/v1/exercises',
      queryParameters: {
        if (filter.query.trim().isNotEmpty) 'q': filter.query.trim(),
        if (filter.muscle != null) 'muscle': filter.muscle,
        if (filter.equipment != null) 'equipment': filter.equipment,
        if (cursor != null) 'cursor': cursor,
        if (limit != null) 'limit': limit,
      },
    );
    return ExercisePage.fromJson(json!);
  }

  Future<Exercise> byId(String id) async {
    final json = await _get<Map<String, dynamic>>('/v1/exercises/$id');
    return Exercise.fromJson(json!);
  }

  /// Cria um exercício **do tenant**. A biblioteca global é somente leitura
  /// (ADR-010 §3): duplicar um global é ler e criar de novo, que é o que a
  /// tela faz.
  Future<Exercise> create({
    required String name,
    required String primaryMuscle,
    required String equipment,
    required String level,
    String instructions = '',
    String? mediaUrl,
    ExerciseMediaType? mediaType,
  }) async {
    final json = await _send<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        '/v1/exercises',
        data: _payload(
          name: name,
          primaryMuscle: primaryMuscle,
          equipment: equipment,
          level: level,
          instructions: instructions,
          mediaUrl: mediaUrl,
          mediaType: mediaType,
        ),
      ),
    );
    return Exercise.fromJson(json!);
  }

  Future<Exercise> update({
    required String id,
    required String name,
    required String primaryMuscle,
    required String equipment,
    required String level,
    String instructions = '',
    String? mediaUrl,
    ExerciseMediaType? mediaType,
    String? status,
  }) async {
    final json = await _send<Map<String, dynamic>>(
      () => _dio.put<Map<String, dynamic>>(
        '/v1/exercises/$id',
        data: _payload(
          name: name,
          primaryMuscle: primaryMuscle,
          equipment: equipment,
          level: level,
          instructions: instructions,
          mediaUrl: mediaUrl,
          mediaType: mediaType,
          status: status,
        ),
      ),
    );
    return Exercise.fromJson(json!);
  }

  /// Sobe a mídia do exercício em duas etapas (P1.2): pede a URL assinada ao
  /// `workout` e faz o PUT direto no storage — os bytes nunca passam pelo
  /// serviço.
  ///
  /// O tamanho vai na assinatura, então o arquivo enviado tem de ser
  /// exatamente o que foi anunciado; por isso [bytes] já vem carregado.
  Future<MediaUploadTarget> uploadMedia({
    required Uint8List bytes,
    required String contentType,
  }) async {
    final json = await _send<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        '/v1/media/presign',
        data: {'content_type': contentType, 'size_bytes': bytes.length},
      ),
    );
    final target = MediaUploadTarget.fromJson(json!);

    // O PUT vai para o storage, não para a API: um Dio limpo, sem baseUrl
    // nem os interceptors de sessão (mandar o Authorization junto quebraria a
    // assinatura em alguns provedores).
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
    return target;
  }

  Map<String, dynamic> _payload({
    required String name,
    required String primaryMuscle,
    required String equipment,
    required String level,
    required String instructions,
    String? mediaUrl,
    ExerciseMediaType? mediaType,
    String? status,
  }) {
    return {
      'name': name,
      'primary_muscle': primaryMuscle,
      'equipment': equipment,
      'level': level,
      'instructions': instructions,
      if (mediaUrl != null && mediaUrl.isNotEmpty) 'media_url': mediaUrl,
      if (mediaType != null) 'media_type': mediaType.code,
      if (status != null) 'status': status,
    };
  }

  Future<T?> _get<T>(String path, {Map<String, dynamic>? queryParameters}) {
    return _send<T>(
      () => _dio.get<T>(path, queryParameters: queryParameters),
    );
  }

  /// Desembrulha o [ApiException] que o `ErrorMappingInterceptor` anexa ao
  /// [DioException]: sem isto, `catch on ApiException` na apresentação nunca
  /// casaria, porque o Dio sempre lança `DioException`.
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
