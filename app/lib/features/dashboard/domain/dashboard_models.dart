/// Contagens de alunos do `identity` (`GET /v1/students/stats`).
class StudentStats {
  const StudentStats({
    required this.active,
    required this.inactive,
    required this.pendingInvites,
    required this.newThisMonth,
  });

  factory StudentStats.fromJson(Map<String, dynamic> json) => StudentStats(
        active: json['active'] as int? ?? 0,
        inactive: json['inactive'] as int? ?? 0,
        pendingInvites: json['pending_invites'] as int? ?? 0,
        newThisMonth: json['new_this_month'] as int? ?? 0,
      );

  final int active;
  final int inactive;
  final int pendingInvites;
  final int newThisMonth;
}

/// Estado de um aluno hoje (`GET /v1/coach/today`).
enum TodayState {
  trained,
  inProgress,
  pending,
  noPlan;

  static TodayState parse(String? raw) => switch (raw) {
        'trained' => TodayState.trained,
        'in_progress' => TodayState.inProgress,
        'pending' => TodayState.pending,
        _ => TodayState.noPlan,
      };
}

class TodayItem {
  const TodayItem({
    required this.studentId,
    required this.state,
    this.lastSessionAt,
    this.stale = false,
  });

  factory TodayItem.fromJson(Map<String, dynamic> json) {
    final last = json['last_session_at'] as String?;
    return TodayItem(
      studentId: json['student_id'] as String,
      state: TodayState.parse(json['state'] as String?),
      lastSessionAt: last == null ? null : DateTime.parse(last).toLocal(),
      stale: json['stale'] as bool? ?? false,
    );
  }

  final String studentId;
  final TodayState state;
  final DateTime? lastSessionAt;

  /// O servidor marca como `stale` também quem nunca treinou.
  final bool stale;
}

class CoachToday {
  const CoachToday({required this.items});

  factory CoachToday.fromJson(Map<String, dynamic> json) => CoachToday(
        items: [
          for (final raw in json['items'] as List<dynamic>? ?? const [])
            TodayItem.fromJson(raw as Map<String, dynamic>),
        ],
      );

  final List<TodayItem> items;

  int count(TodayState state) => items.where((i) => i.state == state).length;

  /// Alunos de hoje que valem uma linha na lista: quem já treinou, está
  /// treinando ou ainda deve treino. `no_plan` entra só como contagem.
  List<TodayItem> get listed =>
      items.where((i) => i.state != TodayState.noPlan).toList()
        ..sort((a, b) => a.state.index.compareTo(b.state.index));

  /// "Sem treinar há 7+ dias": quem já treinou alguma vez e parou. Quem nunca
  /// treinou não entra aqui (aluno novo não é abandono; se tem plano, já
  /// aparece como pendente hoje) — decisão da P8.2.
  List<TodayItem> get stalled =>
      items.where((i) => i.stale && i.lastSessionAt != null).toList()
        ..sort((a, b) => a.lastSessionAt!.compareTo(b.lastSessionAt!));
}

class MonthReceived {
  const MonthReceived({required this.period, required this.receivedCents});

  final String period;
  final int receivedCents;
}

/// Resumo financeiro do owner (`GET /v1/billing/summary`), em centavos.
class BillingSummary {
  const BillingSummary({
    required this.period,
    required this.currency,
    required this.receivedCents,
    required this.toReceiveCents,
    required this.toReceiveCount,
    required this.overdueCents,
    required this.overdueCount,
    required this.delinquentStudents,
    required this.series,
  });

  factory BillingSummary.fromJson(Map<String, dynamic> json) => BillingSummary(
        period: json['period'] as String? ?? '',
        currency: json['currency'] as String? ?? 'BRL',
        receivedCents: json['received_cents'] as int? ?? 0,
        toReceiveCents: json['to_receive_cents'] as int? ?? 0,
        toReceiveCount: json['to_receive_count'] as int? ?? 0,
        overdueCents: json['overdue_cents'] as int? ?? 0,
        overdueCount: json['overdue_count'] as int? ?? 0,
        delinquentStudents: json['delinquent_students'] as int? ?? 0,
        series: [
          for (final raw
              in json['received_series'] as List<dynamic>? ?? const [])
            MonthReceived(
              period: (raw as Map<String, dynamic>)['period'] as String? ?? '',
              receivedCents: raw['received_cents'] as int? ?? 0,
            ),
        ],
      );

  final String period;
  final String currency;
  final int receivedCents;
  final int toReceiveCents;
  final int toReceiveCount;
  final int overdueCents;
  final int overdueCount;
  final int delinquentStudents;
  final List<MonthReceived> series;
}
