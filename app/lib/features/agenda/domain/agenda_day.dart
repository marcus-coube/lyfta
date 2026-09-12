import 'agenda_session.dart';
import 'rotation_pointer.dart';

/// Os três estados de uma célula da agenda (P4.1 Aceite): o que já aconteceu
/// pesa mais que qualquer projeção — um dia com sessão sincronizada é
/// sempre [done], mesmo que a rotação tivesse previsto outra coisa.
enum AgendaDayState { predicted, done, rest }

/// Uma célula da agenda semanal/mensal: o que aconteceu (ou deve acontecer,
/// por projeção) num dia do calendário.
class AgendaDay {
  const AgendaDay({
    required this.date,
    required this.state,
    this.dayLabel,
    this.dayTitle,
    this.sessions = const [],
  });

  /// Meia-noite local do dia — chave estável para comparação/lookup.
  final DateTime date;
  final AgendaDayState state;

  /// Rótulo do rodízio (A/B/C…): da sessão feita quando [state] é [AgendaDayState.done],
  /// da projeção quando é [AgendaDayState.predicted]; nulo em descanso.
  final String? dayLabel;
  final String? dayTitle;

  /// Sessões sincronizadas nesse dia. Vazio a menos que [state] seja
  /// [AgendaDayState.done] — normalmente uma só, mas nada no contrato do
  /// P1.5 impede duas (ex.: sessão aberta e abandonada, depois refeita).
  final List<AgendaSession> sessions;

  int get totalSets => sessions.fold(0, (sum, s) => sum + s.totalSets);

  double get totalVolumeKg =>
      sessions.fold(0.0, (sum, s) => sum + s.totalVolumeKg);

  /// Soma das durações das sessões que foram concluídas (`finished_at` não
  /// nulo) — sessão aberta e nunca fechada não entra na conta.
  Duration get totalDuration => sessions.fold(
        Duration.zero,
        (sum, s) => sum + (s.duration ?? Duration.zero),
      );
}

/// Monta a lista de células entre [from] (inclusive) e [to] (exclusivo), um
/// dia por posição.
///
/// Regra de precedência: sessão sincronizada manda sempre (ADR-003 é a fonte
/// de verdade do que aconteceu); um dia passado sem sessão é descanso — sem
/// tentar adivinhar por que o aluno não treinou; só dia de hoje em diante sem
/// sessão ainda usa a projeção da rotação.
List<AgendaDay> buildAgendaDays({
  required DateTime from,
  required DateTime to,
  required DateTime today,
  required Map<DateTime, List<AgendaSession>> sessionsByDay,
  required RotationPointer pointer,
}) {
  final days = <AgendaDay>[];
  final todayKey = DateTime(today.year, today.month, today.day);

  for (var d = from; d.isBefore(to); d = d.add(const Duration(days: 1))) {
    final key = DateTime(d.year, d.month, d.day);
    final sessions = sessionsByDay[key] ?? const [];

    if (sessions.isNotEmpty) {
      days.add(
        AgendaDay(
          date: key,
          state: AgendaDayState.done,
          dayLabel: sessions.first.dayLabel,
          sessions: sessions,
        ),
      );
      continue;
    }

    if (key.isBefore(todayKey)) {
      days.add(AgendaDay(date: key, state: AgendaDayState.rest));
      continue;
    }

    final predicted = pointer.predict(key.difference(todayKey).inDays);
    days.add(
      predicted == null
          ? AgendaDay(date: key, state: AgendaDayState.rest)
          : AgendaDay(
              date: key,
              state: AgendaDayState.predicted,
              dayLabel: predicted.label,
              dayTitle: predicted.title,
            ),
    );
  }
  return days;
}
