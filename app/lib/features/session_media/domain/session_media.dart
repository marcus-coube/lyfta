import 'dart:typed_data';

/// Limites do servidor (ADR-020, P12.1): o app confere antes de gastar rede.
const int sessionMediaMaxBytes = 20 * 1024 * 1024;
const int sessionMediaMaxPerSession = 3;
const int sessionMediaNoteMaxLength = 280;

/// Mídia de execução já registrada no `comms` (`GET /v1/me/session-media`).
class SessionMedia {
  const SessionMedia({
    required this.id,
    required this.contentType,
    required this.createdAt,
    required this.deleteAfter,
    this.studentId = '',
    this.sessionClientId = '',
    this.exerciseName,
    this.note,
    this.ackedAt,
    this.deletedAt,
    this.mediaUrl,
  });

  factory SessionMedia.fromJson(Map<String, dynamic> json) {
    DateTime? date(String key) {
      final raw = json[key] as String?;
      return raw == null || raw.isEmpty ? null : DateTime.parse(raw).toLocal();
    }

    String? text(String key) {
      final raw = json[key] as String?;
      return raw == null || raw.isEmpty ? null : raw;
    }

    return SessionMedia(
      id: json['id'] as String,
      contentType: json['content_type'] as String? ?? '',
      createdAt: date('created_at') ?? DateTime.now(),
      deleteAfter: date('delete_after') ?? DateTime.now(),
      studentId: json['student_id'] as String? ?? '',
      sessionClientId: json['session_client_id'] as String? ?? '',
      exerciseName: text('exercise_name'),
      note: text('note'),
      ackedAt: date('acked_at'),
      deletedAt: date('deleted_at'),
      mediaUrl: text('media_url'),
    );
  }

  final String id;
  final String contentType;
  final DateTime createdAt;
  final DateTime deleteAfter;
  final String studentId;
  final String sessionClientId;
  final String? exerciseName;
  final String? note;

  /// Quando o professor viu ou respondeu.
  final DateTime? ackedAt;

  /// Preenchido quando o job apagou o objeto (a linha fica, a chave some).
  final DateTime? deletedAt;

  /// GET assinado de 15 min; ausente depois da expiração.
  final String? mediaUrl;

  /// Mesma mídia com o estado de ciência de [other] (a URL assinada antiga
  /// segue valendo por 15 min).
  SessionMedia withAck(SessionMedia other) => SessionMedia(
        id: id,
        contentType: contentType,
        createdAt: createdAt,
        deleteAfter: other.deleteAfter,
        studentId: studentId,
        sessionClientId: sessionClientId,
        exerciseName: exerciseName,
        note: note,
        ackedAt: other.ackedAt,
        deletedAt: other.deletedAt,
        mediaUrl: mediaUrl,
      );

  bool get isVideo => contentType.startsWith('video/');
  bool get isSeen => ackedAt != null;
  bool get isExpired => deletedAt != null;
}

/// Página da listagem do professor (`GET /v1/session-media`).
class SessionMediaPage {
  const SessionMediaPage({required this.items, this.nextCursor});

  final List<SessionMedia> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// Arquivo já escolhido e comprimido, pronto para o upload.
class PreparedMedia {
  const PreparedMedia({
    required this.bytes,
    required this.contentType,
    required this.isVideo,
    this.name = '',
  });

  final Uint8List bytes;
  final String contentType;
  final bool isVideo;
  final String name;

  int get sizeBytes => bytes.length;
  bool get exceedsLimit => sizeBytes > sessionMediaMaxBytes;
}
