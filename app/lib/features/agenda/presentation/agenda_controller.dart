import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/agenda_repository.dart';
import '../domain/agenda_day.dart';

/// Semanas olhadas para trás no cálculo do streak (P4.1: "contador local e
/// simples" — 8 semanas é histórico suficiente sem virar relatório).
const int agendaStreakLookbackWeeks = 8;

/// Início da semana da agenda: sempre **domingo**, não o primeiro dia da
/// semana do `Localizations` da tela — o plano pede explicitamente
/// "strip semanal (dom–sáb)", formato de produto e não convenção de locale.
DateTime startOfWeek(DateTime date) {
  final atMidnight = DateTime(date.year, date.month, date.day);
  return atMidnight.subtract(Duration(days: atMidnight.weekday % 7));
}

/// Estado pronto da agenda: a semana visível, o mês expandido (opcional) e o
/// streak (P4.1).
class AgendaView {
  const AgendaView({
    required this.weekStart,
    required this.weekDays,
    required this.monthExpanded,
    required this.focusedMonth,
    required this.monthDays,
    required this.streakWeeks,
  });

  /// Domingo da semana visível na strip.
  final DateTime weekStart;

  /// Exatamente 7 células, domingo a sábado.
  final List<AgendaDay> weekDays;

  final bool monthExpanded;

  /// Mês mostrado na grade expandida (só relevante quando [monthExpanded]).
  final DateTime focusedMonth;
  final List<AgendaDay> monthDays;

  /// Semanas consecutivas (mais recentes primeiro, sem contar a semana
  /// corrente, ainda em andamento) em que o aluno bateu a meta de treinos.
  final int streakWeeks;
}

final agendaControllerProvider =
    AsyncNotifierProvider<AgendaController, AgendaView>(AgendaController.new);

/// Controller da agenda semanal do aluno (P4.1).
///
/// Os campos privados (semana/mês focados) sobrevivem a `invalidateSelf()`
/// porque o Riverpod reusa a mesma instância do `AsyncNotifier` entre
/// rebuilds — mesmo padrão do cursor em `MeasurementsController`
/// (`features/evolution/presentation/measurements_controller.dart`).
class AgendaController extends AsyncNotifier<AgendaView> {
  DateTime _weekStart = startOfWeek(DateTime.now());
  bool _monthExpanded = false;
  DateTime _focusedMonth = DateTime.now();

  @override
  Future<AgendaView> build() => _load();

  Future<void> previousWeek() => _mutate(() {
        _weekStart = _weekStart.subtract(const Duration(days: 7));
      });

  Future<void> nextWeek() => _mutate(() {
        _weekStart = _weekStart.add(const Duration(days: 7));
      });

  Future<void> goToCurrentWeek() => _mutate(() {
        _weekStart = startOfWeek(DateTime.now());
      });

  Future<void> toggleMonth() => _mutate(() {
        _monthExpanded = !_monthExpanded;
        if (_monthExpanded) _focusedMonth = _weekStart;
      });

  /// Um dia tocado na grade do mês vira a semana visível na strip — a agenda
  /// sempre volta a mostrar a semana em detalhe, o mês é só navegação.
  Future<void> selectDay(DateTime day) => _mutate(() {
        _weekStart = startOfWeek(day);
        _focusedMonth = DateTime(day.year, day.month);
      });

  /// Recarrega sem mudar semana/mês em foco — puxão-para-atualizar e "tentar
  /// de novo" depois de erro.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> _mutate(void Function() apply) async {
    apply();
    ref.invalidateSelf();
    await future;
  }

  Future<AgendaView> _load() async {
    final repo = ref.read(agendaRepositoryProvider);
    final today = DateTime.now();
    final weekEnd = _weekStart.add(const Duration(days: 7));

    final currentWeekStart = startOfWeek(today);
    final streakStart = currentWeekStart
        .subtract(const Duration(days: 7 * agendaStreakLookbackWeeks));

    DateTime? monthStart;
    DateTime? monthEnd;
    if (_monthExpanded) {
      monthStart = DateTime(_focusedMonth.year, _focusedMonth.month);
      monthEnd = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    }

    // Uma janela só cobrindo semana visível + mês expandido (se houver) +
    // histórico do streak: uma chamada de sessões serve as três leituras.
    final candidatesFrom = [
      _weekStart,
      streakStart,
      if (monthStart != null) monthStart,
    ];
    final candidatesTo = [
      weekEnd,
      currentWeekStart,
      if (monthEnd != null) monthEnd,
    ];
    final rangeFrom = candidatesFrom.reduce((a, b) => a.isBefore(b) ? a : b);
    final rangeTo = candidatesTo.reduce((a, b) => a.isAfter(b) ? a : b);

    final pointer = await repo.rotationPointer();
    final sessionsByDay = await repo.sessionsByDay(rangeFrom, rangeTo);

    final weekDays = buildAgendaDays(
      from: _weekStart,
      to: weekEnd,
      today: today,
      sessionsByDay: sessionsByDay,
      pointer: pointer,
    );

    final monthDays = _monthExpanded
        ? buildAgendaDays(
            from: monthStart!,
            to: monthEnd!,
            today: today,
            sessionsByDay: sessionsByDay,
            pointer: pointer,
          )
        : const <AgendaDay>[];

    // Meta semanal simples: o tamanho do rodízio (A/B/C → 3), sem histórico
    // de metas nem configuração — gamificação de verdade é 3.0 (ADR-012).
    final weeklyTarget = pointer.days.isEmpty ? 1 : pointer.days.length;
    var streakWeeks = 0;
    for (var i = 0; i < agendaStreakLookbackWeeks; i++) {
      final weekStart = currentWeekStart.subtract(Duration(days: 7 * (i + 1)));
      final weekEndExclusive = currentWeekStart.subtract(Duration(days: 7 * i));
      var count = 0;
      for (var d = weekStart;
          d.isBefore(weekEndExclusive);
          d = d.add(const Duration(days: 1))) {
        count += sessionsByDay[d]?.length ?? 0;
      }
      if (count < weeklyTarget) break;
      streakWeeks++;
    }

    return AgendaView(
      weekStart: _weekStart,
      weekDays: weekDays,
      monthExpanded: _monthExpanded,
      focusedMonth: _focusedMonth,
      monthDays: monthDays,
      streakWeeks: streakWeeks,
    );
  }
}
