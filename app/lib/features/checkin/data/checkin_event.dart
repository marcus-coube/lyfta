/// Dor forte relatada num check-in (`checkin.pain_strong`, P3.3) — o `comms`
/// publica isto no mesmo socket do chat (`core/realtime/`); a fila de
/// check-ins do coach (P3.5 §3) recarrega quando chega um evento deste tipo
/// para o aluno que ela está mostrando.
class CheckinPainStrongEvent {
  const CheckinPainStrongEvent({
    required this.checkinId,
    required this.studentId,
  });

  final String checkinId;
  final String studentId;

  static CheckinPainStrongEvent? fromJson(Map<String, dynamic> json) {
    if (json['type'] != 'checkin.pain_strong') return null;
    return CheckinPainStrongEvent(
      checkinId: json['checkin_id'] as String? ?? '',
      studentId: json['student_id'] as String? ?? '',
    );
  }
}
