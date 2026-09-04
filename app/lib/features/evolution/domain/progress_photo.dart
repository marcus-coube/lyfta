/// Pose da foto de evolução — mesmo enum do schema do `assessment` (P2.2):
/// `front|side|back`.
enum Pose {
  front,
  side,
  back;

  static Pose? tryParse(String? raw) => switch (raw) {
        'front' => Pose.front,
        'side' => Pose.side,
        'back' => Pose.back,
        _ => null,
      };

  String get code => name;
}

/// Uma foto de evolução (`assessment`, P2.3). [mediaUrl] já vem assinada
/// para leitura — o app nunca monta a URL do storage sozinho.
class ProgressPhoto {
  const ProgressPhoto({
    required this.id,
    required this.studentId,
    required this.takenAt,
    required this.pose,
    required this.mediaUrl,
    required this.createdAt,
    this.notes = '',
  });

  factory ProgressPhoto.fromJson(Map<String, dynamic> json) {
    return ProgressPhoto(
      id: json['id'] as String,
      studentId: json['student_id'] as String? ?? '',
      takenAt: DateTime.parse(json['taken_at'] as String),
      pose: Pose.tryParse(json['pose'] as String?) ?? Pose.front,
      mediaUrl: json['media_url'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String studentId;
  final DateTime takenAt;
  final Pose pose;
  final String mediaUrl;
  final String notes;
  final DateTime createdAt;
}

/// Destino de upload devolvido por `POST /v1/{me|students/{id}}/media/presign`
/// do `assessment` (P2.3) — layout diferente do presign do `workout` (P1.2):
/// aqui a resposta carrega a `key` crua, não uma `media_url` pronta, porque
/// `progress_photos.media_key` grava a key, não uma URL.
class AssessmentUploadTarget {
  const AssessmentUploadTarget({
    required this.uploadUrl,
    required this.method,
    required this.headers,
    required this.key,
    required this.expiresAt,
  });

  factory AssessmentUploadTarget.fromJson(Map<String, dynamic> json) {
    return AssessmentUploadTarget(
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
