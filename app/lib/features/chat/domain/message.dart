import 'dart:typed_data';

/// Tipo de conteúdo de uma mensagem — texto ou imagem (ADR-012 §2 restringe
/// o MVP a esses dois; mídia rica fica pro 3.0). Mesmo código do `comms`
/// (`domain.MessageType`).
enum MessageType {
  text,
  image;

  static MessageType fromCode(String? code) => switch (code) {
        'image' => MessageType.image,
        _ => MessageType.text,
      };

  String get code => name;
}

/// Uma mensagem já confirmada pelo servidor (`GET/POST
/// /v1/conversations/{id}/messages`, P3.2). [mediaUrl] já vem assinada para
/// leitura — o app nunca monta a URL do storage sozinho.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.type,
    required this.createdAt,
    this.body = '',
    this.mediaUrl = '',
    this.readAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String? ?? '',
      senderId: json['sender_id'] as String? ?? '',
      type: MessageType.fromCode(json['type'] as String?),
      body: json['body'] as String? ?? '',
      mediaUrl: json['media_url'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      readAt: json['read_at'] == null
          ? null
          : DateTime.parse(json['read_at'] as String).toLocal(),
    );
  }

  final String id;
  final String conversationId;
  final String senderId;
  final MessageType type;
  final String body;
  final String mediaUrl;
  final DateTime createdAt;
  final DateTime? readAt;

  ChatMessage copyWith({DateTime? readAt}) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      type: type,
      body: body,
      mediaUrl: mediaUrl,
      createdAt: createdAt,
      readAt: readAt ?? this.readAt,
    );
  }
}

/// Uma página de histórico (`GET .../messages`, cursor keyset desc — a mais
/// recente vem primeiro, igual o servidor devolve).
class ChatMessagePage {
  const ChatMessagePage({required this.items, this.nextCursor});

  final List<ChatMessage> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// Estado de uma mensagem que a tela mandou e ainda não confirmou (envio
/// otimista, P3.5 §1). O chat não tem fila offline — ao contrário da
/// execução de treino, ADR-003 §1 restringe offline a isso —, então uma
/// falha aqui é definitiva até o usuário tocar em "tentar de novo".
enum PendingStatus { sending, failed }

/// Uma mensagem ainda não confirmada pelo servidor — some da lista assim
/// que a resposta do `POST` chega e vira um [ChatMessage] de verdade.
class PendingMessage {
  const PendingMessage({
    required this.localId,
    required this.type,
    required this.senderId,
    required this.createdAt,
    this.body = '',
    this.imageBytes,
    this.status = PendingStatus.sending,
  });

  final String localId;
  final MessageType type;
  final String senderId;
  final String body;
  final Uint8List? imageBytes;
  final DateTime createdAt;
  final PendingStatus status;

  PendingMessage copyWith({PendingStatus? status}) {
    return PendingMessage(
      localId: localId,
      type: type,
      senderId: senderId,
      body: body,
      imageBytes: imageBytes,
      createdAt: createdAt,
      status: status ?? this.status,
    );
  }
}

/// Destino de upload devolvido por `POST
/// /v1/conversations/{id}/media/presign` (P3.2) — mesmo formato do presign
/// do `workout` (P1.2): a `key` só serve para o `POST .../messages` de
/// `media_key`, a leitura sempre é pela `media_url` assinada do próprio
/// [ChatMessage].
class ChatUploadTarget {
  const ChatUploadTarget({
    required this.uploadUrl,
    required this.method,
    required this.headers,
    required this.key,
    required this.expiresAt,
  });

  factory ChatUploadTarget.fromJson(Map<String, dynamic> json) {
    return ChatUploadTarget(
      uploadUrl: json['upload_url'] as String,
      method: json['upload_method'] as String? ?? 'PUT',
      headers: (json['required_headers'] as Map<String, dynamic>? ?? const {})
          .map((key, value) => MapEntry(key, value as String)),
      key: json['key'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  final String uploadUrl;
  final String method;
  final Map<String, String> headers;
  final String key;
  final DateTime expiresAt;
}
