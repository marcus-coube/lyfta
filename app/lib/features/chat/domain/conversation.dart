import 'message.dart';

/// Uma conversa (`GET /v1/conversations`, P3.2) — o par aluno-coach, com a
/// prévia da última mensagem e o contador de não lidas do ponto de vista de
/// quem pediu a lista.
class Conversation {
  const Conversation({
    required this.id,
    required this.studentId,
    required this.coachId,
    required this.createdAt,
    this.lastMessageAt,
    this.lastMessage,
    this.unreadCount = 0,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final lastMessageRaw = json['last_message'] as Map<String, dynamic>?;
    return Conversation(
      id: json['id'] as String,
      studentId: json['student_id'] as String? ?? '',
      coachId: json['coach_id'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      lastMessageAt: json['last_message_at'] == null
          ? null
          : DateTime.parse(json['last_message_at'] as String).toLocal(),
      lastMessage:
          lastMessageRaw == null ? null : ChatMessage.fromJson(lastMessageRaw),
      unreadCount: json['unread_count'] as int? ?? 0,
    );
  }

  final String id;
  final String studentId;
  final String coachId;
  final DateTime createdAt;
  final DateTime? lastMessageAt;
  final ChatMessage? lastMessage;
  final int unreadCount;

  /// O outro participante, do ponto de vista de [selfId] — o professor de um
  /// aluno, ou o aluno de um professor.
  String otherParticipant(String selfId) =>
      selfId == coachId ? studentId : coachId;
}
