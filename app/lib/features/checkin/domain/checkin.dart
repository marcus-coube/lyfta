/// Dor relatada no check-in de treino (P3.3) — `strong` dispara push
/// imediato pro coach (P3.4). Mesmo código do `comms` (`domain.PainLevel`).
enum PainLevel {
  none,
  mild,
  strong;

  static PainLevel fromCode(String? code) => switch (code) {
        'mild' => PainLevel.mild,
        'strong' => PainLevel.strong,
        _ => PainLevel.none,
      };

  String get code => name;
}

/// O que a tela de avaliação pós-treino manda (`POST /v1/checkins`, P3.3) —
/// `sessionClientId` é o mesmo `client_id` da sessão no `workout` (ADR-003
/// §2), sem FK entre bancos (ADR-013 §2).
class CheckinDraft {
  const CheckinDraft({
    required this.sessionClientId,
    required this.rating,
    required this.difficulty,
    required this.pain,
    this.painNotes = '',
    this.comment = '',
  });

  final String sessionClientId;
  final int rating;
  final int difficulty;
  final PainLevel pain;
  final String painNotes;
  final String comment;

  Map<String, dynamic> toJson() => {
        'session_client_id': sessionClientId,
        'rating': rating,
        'difficulty': difficulty,
        'pain': pain.code,
        'pain_notes': painNotes,
        'comment': comment,
      };

  factory CheckinDraft.fromJson(Map<String, dynamic> json) {
    return CheckinDraft(
      sessionClientId: json['session_client_id'] as String,
      rating: json['rating'] as int,
      difficulty: json['difficulty'] as int,
      pain: PainLevel.fromCode(json['pain'] as String?),
      painNotes: json['pain_notes'] as String? ?? '',
      comment: json['comment'] as String? ?? '',
    );
  }
}

/// Um check-in já confirmado pelo servidor — o que a fila do coach lista
/// (`GET /v1/checkins`, P3.3).
class WorkoutCheckin {
  const WorkoutCheckin({
    required this.id,
    required this.studentId,
    required this.sessionClientId,
    required this.rating,
    required this.difficulty,
    required this.pain,
    required this.createdAt,
    this.painNotes = '',
    this.comment = '',
    this.reviewedBy = '',
    this.reviewedAt,
  });

  factory WorkoutCheckin.fromJson(Map<String, dynamic> json) {
    return WorkoutCheckin(
      id: json['id'] as String,
      studentId: json['student_id'] as String? ?? '',
      sessionClientId: json['session_client_id'] as String? ?? '',
      rating: json['rating'] as int? ?? 0,
      difficulty: json['difficulty'] as int? ?? 0,
      pain: PainLevel.fromCode(json['pain'] as String?),
      painNotes: json['pain_notes'] as String? ?? '',
      comment: json['comment'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      reviewedBy: json['reviewed_by'] as String? ?? '',
      reviewedAt: json['reviewed_at'] == null
          ? null
          : DateTime.parse(json['reviewed_at'] as String).toLocal(),
    );
  }

  final String id;
  final String studentId;
  final String sessionClientId;
  final int rating;
  final int difficulty;
  final PainLevel pain;
  final String painNotes;
  final String comment;
  final DateTime createdAt;
  final String reviewedBy;
  final DateTime? reviewedAt;

  bool get isReviewed => reviewedAt != null;

  WorkoutCheckin copyWith({String? reviewedBy, DateTime? reviewedAt}) {
    return WorkoutCheckin(
      id: id,
      studentId: studentId,
      sessionClientId: sessionClientId,
      rating: rating,
      difficulty: difficulty,
      pain: pain,
      painNotes: painNotes,
      comment: comment,
      createdAt: createdAt,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewedAt: reviewedAt ?? this.reviewedAt,
    );
  }
}

/// Uma página da fila de check-ins (cursor keyset de 3 campos do P3.3).
class CheckinPage {
  const CheckinPage({required this.items, this.nextCursor});

  final List<WorkoutCheckin> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}
