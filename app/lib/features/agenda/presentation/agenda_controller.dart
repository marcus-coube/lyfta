import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../evolution/domain/evolution_scope.dart';
import '../../profile/data/profile_repository.dart';
import '../data/agenda_repository.dart';
import '../domain/agenda_day.dart';

/// Semanas olhadas para trás no cálculo do streak (P4.1: "contador local e
/// simples" — 8 semanas é histórico suficiente sem virar relatório).
const int agendaStreakLookbackWeeks = 8;

/// Meta semanal do streak (P5.5): a `weekly_target` da anamnese, e só quando
/// ela está vazia o tamanho do rodízio (A/B/C → 3); sem rodízio, 1.
int resolveWeeklyTarget({int? profileTarget, required int rotationLength}) {
  if (profileTarget != null && profileTarget >= 1) return profileTarget;
  return rotationLength == 0 ? 1 : rotationLength;
}

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

  /// `weekly_target` do `assessment`. Qualquer falha (sem consentimento de
  /// saúde, rede) cai no rodízio: a meta é um enfeite da Agenda, nunca motivo
  /// para ela não abrir.
  Future<int?> _profileTarget() async {
    try {
      final profile = await ref
          .read(profileRepositoryProvider)
          .profile(const EvolutionScope.me());
      return profile.weeklyTarget;
    } catch (_) {
      return null;
    }
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
    final profileTarget = await _profileTarget();

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

    // Meta semanal: a da anamnese (P5.5) ou, sem ela, o tamanho do rodízio —
    // sem histórico de metas; gamificação de verdade é 3.0 (ADR-012).
    final weeklyTarget = resolveWeeklyTarget(
      profileTarget: profileTarget,
      rotationLength: pointer.days.length,
    );
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
