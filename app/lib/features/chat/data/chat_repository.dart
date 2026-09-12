import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/http/api_exception.dart';
import '../../../core/http/providers.dart';
import '../domain/conversation.dart';
import '../domain/message.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(ref.watch(commsApiClientProvider).dio);
});

/// Repositório do chat (P3.2/P3.5) sobre o serviço `comms`.
///
/// O WebSocket (`chat_socket.dart`) é só entrega quente: toda leitura e
/// escrita de verdade passa por aqui, REST — é o que o Aceite do P3.2 exige
/// ("queda de WS não perde mensagem, REST recupera").
class ChatRepository {
  ChatRepository(this._dio);

  final Dio _dio;

  Future<List<Conversation>> listConversations() async {
    final json = await _get<Map<String, dynamic>>('/v1/conversations');
    return (json!['items'] as List<dynamic>? ?? const [])
        .map((raw) => Conversation.fromJson(raw as Map<String, dynamic>))
        .toList();
  }

  /// Abre (ou recupera) a conversa com um aluno — só coach/owner
  /// (`RequireRole`, P3.2). O aluno nunca chama isto: a dele já existe assim
  /// que o professor iniciar.
  Future<Conversation> startConversation(String studentId) async {
    final json = await _send(
      () => _dio.post<Map<String, dynamic>>(
        '/v1/conversations',
        data: {'student_id': studentId},
      ),
    );
    return Conversation.fromJson(json!);
  }

  Future<ChatMessagePage> listMessages(
    String conversationId, {
    String? cursor,
    int? limit,
  }) async {
    final json = await _get<Map<String, dynamic>>(
      '/v1/conversations/$conversationId/messages',
      query: {
        if (cursor != null) 'cursor': cursor,
        if (limit != null) 'limit': limit,
      },
    );
    final items = (json!['items'] as List<dynamic>? ?? const [])
        .map((raw) => ChatMessage.fromJson(raw as Map<String, dynamic>))
        .toList();
    final cursorOut = json['next_cursor'] as String?;
    return ChatMessagePage(
      items: items,
      nextCursor: (cursorOut ?? '').isEmpty ? null : cursorOut,
    );
  }

  Future<ChatMessage> sendText(String conversationId, String body) async {
    final json = await _send(
      () => _dio.post<Map<String, dynamic>>(
        '/v1/conversations/$conversationId/messages',
        data: {'type': 'text', 'body': body},
      ),
    );
    return ChatMessage.fromJson(json!);
  }

  Future<ChatMessage> sendImage(
    String conversationId,
    String mediaKey,
  ) async {
    final json = await _send(
      () => _dio.post<Map<String, dynamic>>(
        '/v1/conversations/$conversationId/messages',
        data: {'type': 'image', 'media_key': mediaKey},
      ),
    );
    return ChatMessage.fromJson(json!);
  }

  Future<int> markRead(String conversationId) async {
    final json = await _send(
      () => _dio.post<Map<String, dynamic>>(
        '/v1/conversations/$conversationId/read',
      ),
    );
    return json!['marked'] as int? ?? 0;
  }

  /// Pede a URL assinada para o upload (etapa 1 das duas do presign, mesmo
  /// contrato do P1.2/P2.3): o serviço nunca recebe os bytes da imagem.
  Future<ChatUploadTarget> presignImage(
    String conversationId, {
    required String contentType,
    required int sizeBytes,
  }) async {
    final json = await _send(
      () => _dio.post<Map<String, dynamic>>(
        '/v1/conversations/$conversationId/media/presign',
        data: {'content_type': contentType, 'size_bytes': sizeBytes},
      ),
    );
    return ChatUploadTarget.fromJson(json!);
  }

  /// Etapa 2: PUT direto no storage, fora da API — `Dio` limpo, sem
  /// `baseUrl` nem os interceptors de sessão (mesmo padrão do P2.4).
  Future<void> uploadImageBytes(
    ChatUploadTarget target,
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

  Future<T?> _get<T>(String path, {Map<String, dynamic>? query}) {
    return _send<T>(() => _dio.get<T>(path, queryParameters: query));
  }

  /// Desembrulha o [ApiException] que o `ErrorMappingInterceptor` anexa ao
  /// `DioException` (mesmo padrão do `EvolutionRepository`).
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
