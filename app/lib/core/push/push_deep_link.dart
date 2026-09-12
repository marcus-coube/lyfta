/// Para onde uma notificação tocada deve levar o app (P3.5 §4) — construído
/// a partir do `data` do FCM, que é sempre `Map<String, String>` (o mesmo
/// payload que os três tipos de push do MVP carregam, `internal/push` do
/// `comms`: `message.new`, `checkin.pain_strong`, `workout.pending`).
enum PushDeepLinkKind { chat, checkins, workoutToday, none }

class PushDeepLink {
  const PushDeepLink({required this.kind, this.conversationId, this.studentId});

  const PushDeepLink.none() : this(kind: PushDeepLinkKind.none);

  factory PushDeepLink.fromData(Map<String, dynamic> data) {
    switch (data['type']) {
      case 'message.new':
        final conversationId = data['conversation_id'] as String?;
        if (conversationId == null || conversationId.isEmpty) {
          return const PushDeepLink.none();
        }
        return PushDeepLink(
          kind: PushDeepLinkKind.chat,
          conversationId: conversationId,
        );
      case 'checkin.pain_strong':
        final studentId = data['student_id'] as String?;
        if (studentId == null || studentId.isEmpty) {
          return const PushDeepLink.none();
        }
        return PushDeepLink(kind: PushDeepLinkKind.checkins, studentId: studentId);
      case 'workout.pending':
        return const PushDeepLink(kind: PushDeepLinkKind.workoutToday);
      default:
        return const PushDeepLink.none();
    }
  }

  final PushDeepLinkKind kind;
  final String? conversationId;
  final String? studentId;
}
