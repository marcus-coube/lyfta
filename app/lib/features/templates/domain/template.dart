import '../../../core/http/api_exception.dart';

/// Linha da biblioteca de modelos (`GET /v1/templates`, P6.1).
class TemplateSummary {
  const TemplateSummary({
    required this.id,
    required this.title,
    required this.status,
    required this.publishedVersionNo,
    required this.hasDraft,
    required this.daysCount,
    required this.exercisesCount,
    required this.assignedCount,
    this.description = '',
    this.coachId = '',
  });

  factory TemplateSummary.fromJson(Map<String, dynamic> json) {
    return TemplateSummary(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      coachId: json['coach_id'] as String? ?? '',
      status: json['status'] as String? ?? 'draft',
      publishedVersionNo: json['published_version_no'] as int? ?? 0,
      hasDraft: json['has_draft'] as bool? ?? false,
      daysCount: json['days_count'] as int? ?? 0,
      exercisesCount: json['exercises_count'] as int? ?? 0,
      assignedCount: json['assigned_count'] as int? ?? 0,
    );
  }

  final String id;
  final String title;
  final String description;
  final String coachId;
  final String status;
  final int publishedVersionNo;
  final bool hasDraft;
  final int daysCount;
  final int exercisesCount;
  final int assignedCount;

  bool get isArchived => status == 'archived';

  /// Só modelo com versão publicada pode ser atribuído (422
  /// `template_not_published` caso contrário).
  bool get canAssign => !isArchived && publishedVersionNo > 0;
}

class TemplatePage {
  const TemplatePage({required this.items, this.nextCursor});

  final List<TemplateSummary> items;
  final String? nextCursor;
}

/// Resultado de um item de `assign`/`reapply`: o lote nunca falha por causa de
/// um item, cada um traz o próprio erro.
class BatchItem {
  const BatchItem({
    required this.ok,
    this.studentId = '',
    this.planId = '',
    this.versionNo = 0,
    this.error,
  });

  factory BatchItem.fromJson(Map<String, dynamic> json) {
    final error = json['error'] as Map<String, dynamic>?;
    return BatchItem(
      ok: json['ok'] as bool? ?? false,
      studentId: json['student_id'] as String? ?? '',
      planId: json['plan_id'] as String? ?? '',
      versionNo: json['version_no'] as int? ?? 0,
      error: error == null
          ? null
          : ApiException(
              code: error['code'] as String? ?? 'internal_error',
              params: (error['params'] as Map<String, dynamic>?) ?? const {},
            ),
    );
  }

  final bool ok;
  final String studentId;
  final String planId;
  final int versionNo;
  final ApiException? error;
}

/// Plano de aluno criado a partir de um modelo (`GET .../recipients`).
class TemplateRecipient {
  const TemplateRecipient({
    required this.planId,
    required this.studentId,
    required this.title,
    required this.status,
    required this.isActive,
    required this.sourceVersionNo,
    required this.editedAfterSource,
  });

  factory TemplateRecipient.fromJson(Map<String, dynamic> json) {
    return TemplateRecipient(
      planId: json['plan_id'] as String,
      studentId: json['student_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      status: json['status'] as String? ?? 'draft',
      isActive: json['is_active'] as bool? ?? false,
      sourceVersionNo: json['source_version_no'] as int? ?? 0,
      editedAfterSource: json['edited_after_source'] as bool? ?? false,
    );
  }

  final String planId;
  final String studentId;
  final String title;
  final String status;
  final bool isActive;
  final int sourceVersionNo;

  /// O coach mexeu no plano depois de aplicar: reaplicar perde esses ajustes.
  final bool editedAfterSource;

  /// Plano arquivado não é reaplicado (reativaria sem o coach pedir).
  bool get isArchived => status == 'archived';
}

class TemplateRecipients {
  const TemplateRecipients({
    required this.templateVersionNo,
    required this.items,
  });

  /// Versão publicada atual do modelo, para comparar com `sourceVersionNo`.
  final int templateVersionNo;
  final List<TemplateRecipient> items;
}
