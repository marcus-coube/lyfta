/// Taxonomia da biblioteca (ADR-010 §4). São **códigos**, não rótulos: o
/// backend valida contra esta mesma lista e nunca devolve texto de UI — quem
/// traduz é o app (ADR-011 §5).
abstract final class ExerciseTaxonomy {
  static const List<String> muscles = [
    'chest',
    'back',
    'lats',
    'traps',
    'lower_back',
    'shoulders',
    'biceps',
    'triceps',
    'forearms',
    'abs',
    'obliques',
    'quadriceps',
    'hamstrings',
    'glutes',
    'calves',
    'adductors',
    'abductors',
    'full_body',
  ];

  static const List<String> equipment = [
    'barbell',
    'dumbbell',
    'machine',
    'cable',
    'smith',
    'bodyweight',
    'kettlebell',
    'band',
    'bench',
    'other',
  ];

  static const List<String> levels = ['beginner', 'intermediate', 'advanced'];
}

/// Tipo de mídia demonstrativa do exercício.
enum ExerciseMediaType {
  gif,
  video;

  static ExerciseMediaType? tryParse(String? raw) => switch (raw) {
        'gif' => ExerciseMediaType.gif,
        'video' => ExerciseMediaType.video,
        _ => null,
      };

  String get code => name;
}

/// Um item da biblioteca de exercícios (ADR-010).
///
/// [name] e [instructions] já vêm resolvidos no idioma do usuário pelo
/// backend; [locale] diz qual idioma saiu de fato, para a UI poder avisar que
/// caiu no fallback (ADR-011 §2).
class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    required this.primaryMuscle,
    required this.equipment,
    required this.level,
    required this.isGlobal,
    required this.status,
    this.instructions = '',
    this.locale = '',
    this.mediaUrl,
    this.mediaType,
  });

  factory Exercise.fromJson(Map<String, dynamic> json) {
    return Exercise(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      instructions: json['instructions'] as String? ?? '',
      locale: json['locale'] as String? ?? '',
      primaryMuscle: json['primary_muscle'] as String? ?? '',
      equipment: json['equipment'] as String? ?? '',
      level: json['level'] as String? ?? '',
      isGlobal: json['is_global'] as bool? ?? false,
      status: json['status'] as String? ?? 'active',
      mediaUrl: json['media_url'] as String?,
      mediaType: ExerciseMediaType.tryParse(json['media_type'] as String?),
    );
  }

  final String id;
  final String name;
  final String instructions;
  final String locale;
  final String primaryMuscle;
  final String equipment;
  final String level;

  /// Exercício da biblioteca global da Lyfta: legível por todo tenant,
  /// editável por nenhum (ADR-010 §3) — a UI oferece "duplicar" no lugar de
  /// "editar".
  final bool isGlobal;
  final String status;
  final String? mediaUrl;
  final ExerciseMediaType? mediaType;

  bool get hasMedia => (mediaUrl ?? '').isNotEmpty && mediaType != null;
  bool get isArchived => status == 'archived';
}

/// Uma página da biblioteca — os itens e o cursor da página seguinte.
class ExercisePage {
  const ExercisePage({required this.items, this.nextCursor});

  factory ExercisePage.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? const [])
        .map((raw) => Exercise.fromJson(raw as Map<String, dynamic>))
        .toList();
    final cursor = json['next_cursor'] as String?;
    return ExercisePage(
      items: items,
      nextCursor: (cursor ?? '').isEmpty ? null : cursor,
    );
  }

  final List<Exercise> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// Filtros da tela da biblioteca. Campos nulos/vazios não filtram.
class ExerciseFilter {
  const ExerciseFilter({this.query = '', this.muscle, this.equipment});

  final String query;
  final String? muscle;
  final String? equipment;

  ExerciseFilter copyWith({
    String? query,
    String? muscle,
    String? equipment,
    bool clearMuscle = false,
    bool clearEquipment = false,
  }) {
    return ExerciseFilter(
      query: query ?? this.query,
      muscle: clearMuscle ? null : (muscle ?? this.muscle),
      equipment: clearEquipment ? null : (equipment ?? this.equipment),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ExerciseFilter &&
      other.query == query &&
      other.muscle == muscle &&
      other.equipment == equipment;

  @override
  int get hashCode => Object.hash(query, muscle, equipment);
}

/// Destino de upload devolvido por `POST /v1/media/presign` (P1.2): a URL
/// assinada para o PUT e a URL que fica gravada no exercício.
///
/// A assinatura inclui `Content-Type` **e** `Content-Length`, então a URL só
/// aceita exatamente o arquivo que foi anunciado — mandar outro dá 403.
class MediaUploadTarget {
  const MediaUploadTarget({
    required this.uploadUrl,
    required this.headers,
    required this.mediaUrl,
    required this.mediaType,
  });

  factory MediaUploadTarget.fromJson(Map<String, dynamic> json) {
    return MediaUploadTarget(
      uploadUrl: json['upload_url'] as String,
      headers: (json['required_headers'] as Map<String, dynamic>? ?? const {})
          .map((key, value) => MapEntry(key, value as String)),
      mediaUrl: json['media_url'] as String,
      mediaType: ExerciseMediaType.tryParse(json['media_type'] as String?) ??
          ExerciseMediaType.gif,
    );
  }

  final String uploadUrl;
  final Map<String, String> headers;
  final String mediaUrl;
  final ExerciseMediaType mediaType;
}
