import '../domain/message.dart';

/// Evento de chat entregue pelo `CommsSocketService` (JSON cru, `core/
/// realtime/`) — mesmo envelope que os handlers REST do `comms` publicam no
/// Redis (`internal/http/conversations.go`), campo `type` como
/// discriminador. Só entende `message.*`; qualquer outro `type` (ex.:
/// `checkin.pain_strong`, que é do `features/checkin/`) devolve `null` — é
/// assim que duas features escutam o mesmo socket sem uma conhecer a outra.
sealed class ChatEvent {
  const ChatEvent();

  static ChatEvent? fromJson(Map<String, dynamic> json) {
    switch (json['type'] as String?) {
      case 'message.new':
        final message = json['message'] as Map<String, dynamic>?;
        if (message == null) return null;
        return MessageNewEvent(
          conversationId: json['conversation_id'] as String? ?? '',
          message: ChatMessage.fromJson(message),
        );
      case 'message.read':
        return MessageReadEvent(
          conversationId: json['conversation_id'] as String? ?? '',
          readerId: json['reader_id'] as String? ?? '',
          messageIds: (json['message_ids'] as List<dynamic>? ?? const [])
              .map((e) => e as String)
              .toList(),
        );
      default:
        return null;
    }
  }
}

class MessageNewEvent extends ChatEvent {
  const MessageNewEvent({required this.conversationId, required this.message});

  final String conversationId;
  final ChatMessage message;
}

class MessageReadEvent extends ChatEvent {
  const MessageReadEvent({
    required this.conversationId,
    required this.readerId,
    required this.messageIds,
  });

  final String conversationId;
  final String readerId;
  final List<String> messageIds;
}
