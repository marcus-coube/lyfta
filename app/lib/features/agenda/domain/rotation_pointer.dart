/// Um dia do rodízio, visto de fora da árvore de treino — só o rótulo (A/B/C)
/// e o título, que é tudo que a agenda precisa para projetar "treino
/// previsto" (P4.1).
///
/// Espelha `RotationDay` de `features/workout/domain/today.dart`, duplicado
/// de propósito: guideline `flutter.md` — feature não importa feature.
class AgendaRotationDay {
  const AgendaRotationDay({required this.id, required this.label, this.title});

  factory AgendaRotationDay.fromJson(Map<String, dynamic> json) {
    final title = (json['title'] as String? ?? '').trim();
    return AgendaRotationDay(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      title: title.isEmpty ? null : title,
    );
  }

  final String id;
  final String label;
  final String? title;
}

/// O estado da rotação no momento da consulta: o rodízio inteiro, em ordem, e
/// qual dia está agendado para hoje.
///
/// Vem de `GET /v1/me/today` (P1.5) — a agenda não tem endpoint próprio de
/// "previsto": o plano (P4.1) é explícito que a projeção é local, e o
/// servidor só garante o próximo dia real (`next_day_id`, um passo à frente).
/// [currentDayId] é nulo em dia de descanso (`status: rest_day`, quando
/// `student_plan_state.next_day_id` é nulo) ou sem plano nenhum.
class RotationPointer {
  const RotationPointer({required this.days, this.currentDayId});

  factory RotationPointer.fromTodayJson(Map<String, dynamic> json) {
    final rotation = (json['rotation'] as List<dynamic>? ?? const [])
        .map((raw) => AgendaRotationDay.fromJson(raw as Map<String, dynamic>))
        .toList();
    final day = json['day'] as Map<String, dynamic>?;
    final isReady = (json['status'] as String?) == 'ready';
    final currentDayId = isReady ? (day?['id'] as String?) : null;
    return RotationPointer(
      days: rotation,
      currentDayId: currentDayId,
    );
  }

  final List<AgendaRotationDay> days;
  final String? currentDayId;

  /// Rótulo previsto para [daysAhead] dias a partir de hoje (0 = hoje),
  /// **assumindo que o aluno treina todo dia a partir de agora** — é uma
  /// projeção simples sobre o rodízio circular (ADR-004 §3), não uma
  /// promessa: o aluno decide quando treina de verdade, e o `next_day_id`
  /// real só avança quando uma sessão é sincronizada.
  ///
  /// Nulo quando não há rodízio (sem plano) ou nenhum dia agendado para hoje
  /// (dia de descanso) — nesses casos a agenda mostra "descanso" também para
  /// os dias futuros, por falta de um ponto de partida para projetar.
  AgendaRotationDay? predict(int daysAhead) {
    if (days.isEmpty || currentDayId == null) return null;
    final index = days.indexWhere((d) => d.id == currentDayId);
    if (index == -1) return null;
    return days[(index + daysAhead) % days.length];
  }
}
