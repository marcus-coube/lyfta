/// Códigos estáveis da anamnese (P5.3, ADR-011 §5): o servidor guarda o
/// código, o app traduz (`shared/l10n/profile_l10n.dart`).
const List<String> goalCodes = [
  'hypertrophy',
  'weight_loss',
  'strength',
  'conditioning',
  'health',
  'rehab',
  'other',
];

const List<String> experienceCodes = ['beginner', 'intermediate', 'advanced'];

const List<String> bodyRegionCodes = [
  'neck',
  'shoulder',
  'elbow',
  'wrist_hand',
  'upper_back',
  'lower_back',
  'chest',
  'hip',
  'knee',
  'ankle_foot',
  'other',
];

/// Limites do servidor (`assessment`), para o campo não aceitar o que o PUT
/// vai recusar.
const int goalNotesMaxLength = 500;
const int medicalNotesMaxLength = 2000;
const int coachNotesMaxLength = 2000;
const int injuryDescriptionMaxLength = 500;

DateTime? _day(Object? raw) {
  if (raw is! String || raw.length < 10) return null;
  return DateTime.tryParse(raw.substring(0, 10));
}

/// Anamnese do aluno (`/profile`, P5.3). Campo vazio = não informado.
///
/// O `PUT` substitui tudo o que a porta escreve, então a tela sempre devolve
/// o perfil inteiro que leu — inclusive `weeklyTarget` e `goalNotes` — para
/// não apagar o que ela não edita.
class StudentProfile {
  const StudentProfile({
    this.goal,
    this.goalNotes = '',
    this.trainingExperience,
    this.weeklyTarget,
    this.medicalNotes = '',
    this.coachNotes = '',
  });

  factory StudentProfile.fromJson(Map<String, dynamic> json) {
    return StudentProfile(
      goal: json['goal'] as String?,
      goalNotes: json['goal_notes'] as String? ?? '',
      trainingExperience: json['training_experience'] as String?,
      weeklyTarget: json['weekly_target'] as int?,
      medicalNotes: json['medical_notes'] as String? ?? '',
      // Só a porta do coach devolve; a do aluno nem manda a chave.
      coachNotes: json['coach_notes'] as String? ?? '',
    );
  }

  final String? goal;
  final String goalNotes;
  final String? trainingExperience;
  final int? weeklyTarget;
  final String medicalNotes;
  final String coachNotes;
}

/// Lesão ou restrição. Ativa enquanto [resolvedAt] é nulo.
class Injury {
  const Injury({
    required this.id,
    required this.bodyRegion,
    required this.description,
    required this.createdAt,
    this.since,
    this.resolvedAt,
  });

  factory Injury.fromJson(Map<String, dynamic> json) {
    return Injury(
      id: json['id'] as String,
      bodyRegion: json['body_region'] as String,
      description: json['description'] as String? ?? '',
      since: _day(json['since']),
      resolvedAt: _day(json['resolved_at']),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String bodyRegion;
  final String description;
  final DateTime? since;
  final DateTime? resolvedAt;
  final DateTime createdAt;

  bool get active => resolvedAt == null;
}

/// O que o formulário de lesão devolve.
class InjuryInput {
  const InjuryInput({
    required this.bodyRegion,
    required this.description,
    this.since,
  });

  final String bodyRegion;
  final String description;
  final DateTime? since;
}
