/// Plano ativo do aluno (a versão publicada que a rotação usa).
class ActivePlan {
  const ActivePlan({
    required this.id,
    required this.title,
    required this.versionNo,
  });

  factory ActivePlan.fromJson(Map<String, dynamic> json) {
    return ActivePlan(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      versionNo: json['version_no'] as int? ?? 0,
    );
  }

  final String id;
  final String title;
  final int versionNo;
}

/// Resumo do aluno no `workout`: quando o servidor soube do último treino
/// (`received_at` da sessão) e o plano ativo.
class StudentOverview {
  const StudentOverview({this.lastSessionAt, this.activePlan});

  factory StudentOverview.fromJson(Map<String, dynamic> json) {
    final last = json['last_session_at'] as String?;
    final plan = json['active_plan'] as Map<String, dynamic>?;
    return StudentOverview(
      lastSessionAt: last == null ? null : DateTime.parse(last).toLocal(),
      activePlan: plan == null ? null : ActivePlan.fromJson(plan),
    );
  }

  final DateTime? lastSessionAt;
  final ActivePlan? activePlan;
}
