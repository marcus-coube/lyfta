import 'exercise.dart';

/// Tipo de bloco (ADR-004 §1): um exercício "normal" é um bloco `straight`
/// com um exercício só. Códigos, não rótulos — o app é quem traduz.
enum BlockType {
  straight,
  superset,
  dropset,
  restPause,
  circuit;

  static BlockType fromCode(String? code) => switch (code) {
        'superset' => BlockType.superset,
        'dropset' => BlockType.dropset,
        'rest_pause' => BlockType.restPause,
        'circuit' => BlockType.circuit,
        _ => BlockType.straight,
      };

  String get code => switch (this) {
        BlockType.straight => 'straight',
        BlockType.superset => 'superset',
        BlockType.dropset => 'dropset',
        BlockType.restPause => 'rest_pause',
        BlockType.circuit => 'circuit',
      };

  /// Conduzido por rodadas (superset e circuito, P6.5): o descanso do bloco
  /// vale ao fim da rodada; entre exercícios da rodada só se a série pedir.
  bool get isRounds => this == BlockType.superset || this == BlockType.circuit;
}

/// Unidade do alvo de carga da série (ADR-012 §4). `kg` usa
/// [PrescribedSet.targetLoadKg]; as demais usam [PrescribedSet.targetValue].
enum TargetUnit {
  kg,
  percent1rm,
  rpe,
  rir;

  static TargetUnit? tryParse(String? code) => switch (code) {
        'kg' => TargetUnit.kg,
        'percent_1rm' => TargetUnit.percent1rm,
        'rpe' => TargetUnit.rpe,
        'rir' => TargetUnit.rir,
        _ => null,
      };

  String get code => switch (this) {
        TargetUnit.kg => 'kg',
        TargetUnit.percent1rm => 'percent_1rm',
        TargetUnit.rpe => 'rpe',
        TargetUnit.rir => 'rir',
      };

  /// Alvo relativo exige valor (é o CHECK da tabela): %1RM, RPE e RIR não
  /// prescrevem nada sem número.
  bool get needsValue => this != TargetUnit.kg;
}

/// Prescrição estruturada de uma série (ADR-012 §4) — nunca texto livre,
/// porque o gráfico de carga do MVP depende destes campos serem consultáveis.
///
/// Os campos são mutáveis de propósito: esta árvore é o **rascunho que o
/// professor edita na tela**, e um editor de cinco níveis com `copyWith` em
/// cada tecla digitada custaria muito mais do que vale. O que sai daqui e vai
/// para a API é sempre a árvore inteira (`PUT /draft` substitui tudo).
class PrescribedSet {
  PrescribedSet({
    this.repsMin,
    this.repsMax,
    this.targetLoadKg,
    this.targetUnit,
    this.targetValue,
    this.restSeconds,
  });

  factory PrescribedSet.fromJson(Map<String, dynamic> json) {
    return PrescribedSet(
      repsMin: json['reps_min'] as int?,
      repsMax: json['reps_max'] as int?,
      targetLoadKg: (json['target_load_kg'] as num?)?.toDouble(),
      targetUnit: TargetUnit.tryParse(json['target_unit'] as String?),
      targetValue: (json['target_value'] as num?)?.toDouble(),
      restSeconds: json['rest_seconds'] as int?,
    );
  }

  int? repsMin;
  int? repsMax;
  double? targetLoadKg;
  TargetUnit? targetUnit;
  double? targetValue;
  int? restSeconds;

  PrescribedSet copy() => PrescribedSet(
        repsMin: repsMin,
        repsMax: repsMax,
        targetLoadKg: targetLoadKg,
        targetUnit: targetUnit,
        targetValue: targetValue,
        restSeconds: restSeconds,
      );

  Map<String, dynamic> toJson() => {
        'reps_min': repsMin,
        'reps_max': repsMax,
        'target_load_kg': targetLoadKg,
        if (targetUnit != null) 'target_unit': targetUnit!.code,
        'target_value': targetValue,
        'rest_seconds': restSeconds,
      };
}

/// Um exercício dentro de um bloco, com as séries prescritas.
class BlockExercise {
  BlockExercise({
    required this.exerciseId,
    this.exercise,
    this.notes = '',
    List<PrescribedSet>? sets,
  }) : sets = sets ?? [];

  factory BlockExercise.fromJson(Map<String, dynamic> json) {
    final summary = json['exercise'] as Map<String, dynamic>?;
    return BlockExercise(
      exerciseId: json['exercise_id'] as String,
      exercise: summary == null ? null : Exercise.fromJson(summary),
      notes: json['notes'] as String? ?? '',
      sets: (json['sets'] as List<dynamic>? ?? const [])
          .map((raw) => PrescribedSet.fromJson(raw as Map<String, dynamic>))
          .toList(),
    );
  }

  final String exerciseId;

  /// Cópia profunda (duplicar bloco): séries novas, mesmo exercício.
  BlockExercise copy() => BlockExercise(
        exerciseId: exerciseId,
        exercise: exercise,
        notes: notes,
        sets: sets.map((s) => s.copy()).toList(),
      );

  /// Resumo do exercício resolvido pelo backend (nome no idioma do usuário,
  /// mídia reassinada) — é o que evita uma chamada à biblioteca por linha.
  final Exercise? exercise;
  String notes;
  final List<PrescribedSet> sets;

  Map<String, dynamic> toJson() => {
        'exercise_id': exerciseId,
        'notes': notes,
        'sets': sets.map((s) => s.toJson()).toList(),
      };
}

/// Agrupamento de execução: superset, circuito, drop set (ADR-004 §1).
class Block {
  Block({
    this.blockType = BlockType.straight,
    this.restSeconds = 60,
    List<BlockExercise>? exercises,
  }) : exercises = exercises ?? [];

  factory Block.fromJson(Map<String, dynamic> json) {
    return Block(
      blockType: BlockType.fromCode(json['block_type'] as String?),
      restSeconds: json['rest_seconds'] as int? ?? 0,
      exercises: (json['exercises'] as List<dynamic>? ?? const [])
          .map((raw) => BlockExercise.fromJson(raw as Map<String, dynamic>))
          .toList(),
    );
  }

  BlockType blockType;
  int restSeconds;
  final List<BlockExercise> exercises;

  /// Cópia profunda (duplicar bloco/dia).
  Block copy() => Block(
        blockType: blockType,
        restSeconds: restSeconds,
        exercises: exercises.map((e) => e.copy()).toList(),
      );

  Map<String, dynamic> toJson() => {
        'block_type': blockType.code,
        'rest_seconds': restSeconds,
        'exercises': exercises.map((e) => e.toJson()).toList(),
      };
}

/// Um dia da rotação (A, B, C…) dentro de uma versão do plano.
class WorkoutDay {
  WorkoutDay({
    required this.label,
    this.id,
    this.title = '',
    List<Block>? blocks,
  }) : blocks = blocks ?? [];

  factory WorkoutDay.fromJson(Map<String, dynamic> json) {
    return WorkoutDay(
      id: json['id'] as String?,
      label: json['label'] as String? ?? '',
      title: json['title'] as String? ?? '',
      blocks: (json['blocks'] as List<dynamic>? ?? const [])
          .map((raw) => Block.fromJson(raw as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Id do servidor, nulo enquanto o dia só existe na tela.
  final String? id;
  String label;
  String title;
  final List<Block> blocks;

  /// Cópia profunda sem id (duplicar dia): só existe na tela até salvar.
  WorkoutDay copy({required String label}) => WorkoutDay(
        label: label,
        title: title,
        blocks: blocks.map((b) => b.copy()).toList(),
      );

  /// A posição sai da **ordem do array** enviado (P1.4): reordenar é mover o
  /// item na lista, e o cliente não manda índice nenhum.
  Map<String, dynamic> toJson() => {
        'label': label,
        'title': title,
        'blocks': blocks.map((b) => b.toJson()).toList(),
      };
}

/// Cabeçalho de uma versão do plano.
class PlanVersionRef {
  const PlanVersionRef({
    required this.id,
    required this.versionNo,
    required this.isDraft,
  });

  factory PlanVersionRef.fromJson(Map<String, dynamic> json) {
    return PlanVersionRef(
      id: json['id'] as String,
      versionNo: json['version_no'] as int,
      isDraft: json['is_draft'] as bool? ?? false,
    );
  }

  final String id;
  final int versionNo;
  final bool isDraft;
}

/// Linha do histórico de versões (`GET /v1/plans/{id}/versions`, P6.2).
class PlanVersionSummary {
  const PlanVersionSummary({
    required this.versionNo,
    required this.isDraft,
    required this.daysCount,
    required this.exercisesCount,
    this.publishedAt,
    this.publishedBy,
  });

  factory PlanVersionSummary.fromJson(Map<String, dynamic> json) {
    final at = json['published_at'] as String?;
    return PlanVersionSummary(
      versionNo: json['version_no'] as int,
      isDraft: json['is_draft'] as bool? ?? false,
      daysCount: json['days_count'] as int? ?? 0,
      exercisesCount: json['exercises_count'] as int? ?? 0,
      publishedAt: at == null ? null : DateTime.tryParse(at)?.toLocal(),
      publishedBy: json['published_by'] as String?,
    );
  }

  final int versionNo;
  final bool isDraft;
  final int daysCount;
  final int exercisesCount;
  final DateTime? publishedAt;

  /// Quem publicou; versões anteriores à P6.2 não têm autor.
  final String? publishedBy;
}

/// O plano do aluno com a versão carregada (rascunho ou publicada).
class Plan {
  const Plan({
    required this.id,
    required this.studentId,
    required this.title,
    required this.status,
    required this.days,
    required this.versions,
    this.version,
    this.nextDayId,
    this.kind = 'assigned',
    this.description = '',
    this.sourceTemplateId,
  });

  factory Plan.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as Map<String, dynamic>?;
    return Plan(
      id: json['id'] as String,
      studentId: json['student_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      status: json['status'] as String? ?? 'draft',
      version: version == null ? null : PlanVersionRef.fromJson(version),
      days: (version?['days'] as List<dynamic>? ?? const [])
          .map((raw) => WorkoutDay.fromJson(raw as Map<String, dynamic>))
          .toList(),
      versions: (json['versions'] as List<dynamic>? ?? const [])
          .map((raw) => PlanVersionRef.fromJson(raw as Map<String, dynamic>))
          .toList(),
      nextDayId: json['next_day_id'] as String?,
      kind: json['kind'] as String? ?? 'assigned',
      description: json['description'] as String? ?? '',
      sourceTemplateId: json['source_template_id'] as String?,
    );
  }

  final String id;
  final String studentId;
  final String title;
  final String status;

  /// `assigned` (plano de um aluno) ou `template` (modelo do tenant, P6.1).
  final String kind;

  /// Só o modelo tem descrição.
  final String description;
  final String? sourceTemplateId;
  final PlanVersionRef? version;
  final List<WorkoutDay> days;
  final List<PlanVersionRef> versions;
  final String? nextDayId;

  bool get isPublished => status == 'published';
  bool get isTemplate => kind == 'template';

  /// Plano (ou modelo) arquivado é somente leitura: o servidor responde 409
  /// `plan_archived`/`template_archived` a rascunho e publicação. Reativar é
  /// só pelo `activate` (plano) ou `unarchive` (modelo).
  bool get isArchived => status == 'archived';

  /// Número da última versão publicada — 0 quando o plano nunca publicou.
  int get publishedVersionNo => versions
      .where((v) => !v.isDraft)
      .fold(0, (max, v) => v.versionNo > max ? v.versionNo : max);
}

/// Linha da lista de planos de um aluno (visão do professor).
class PlanSummary {
  const PlanSummary({
    required this.id,
    required this.title,
    required this.status,
    required this.publishedVersionNo,
    required this.hasDraft,
    required this.isActive,
    this.kind = 'assigned',
    this.sourceTemplateId,
  });

  factory PlanSummary.fromJson(Map<String, dynamic> json) {
    return PlanSummary(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      status: json['status'] as String? ?? 'draft',
      publishedVersionNo: json['published_version_no'] as int? ?? 0,
      hasDraft: json['has_draft'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? false,
      kind: json['kind'] as String? ?? 'assigned',
      sourceTemplateId: json['source_template_id'] as String?,
    );
  }

  final String id;
  final String title;
  final String status;
  final int publishedVersionNo;
  final bool hasDraft;
  final bool isActive;
  final String kind;

  /// Preenchido quando o plano nasceu de um modelo (ADR-018).
  final String? sourceTemplateId;

  bool get isArchived => status == 'archived';
}
