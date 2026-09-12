import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/features/agenda/domain/agenda_day.dart';
import 'package:lyfta/features/agenda/domain/agenda_session.dart';
import 'package:lyfta/features/agenda/domain/rotation_pointer.dart';

RotationPointer _pointer({required String currentDayId}) {
  return RotationPointer(
    days: const [
      AgendaRotationDay(id: 'a', label: 'A'),
      AgendaRotationDay(id: 'b', label: 'B'),
      AgendaRotationDay(id: 'c', label: 'C'),
    ],
    currentDayId: currentDayId,
  );
}

AgendaSession _session(DateTime startedAt) {
  return AgendaSession(
    id: 's1',
    dayLabel: 'A',
    startedAt: startedAt,
    totalSets: 6,
    totalVolumeKg: 300,
  );
}

void main() {
  group('RotationPointer.predict', () {
    test('projeta o rodízio circular a partir do dia de hoje', () {
      final pointer = _pointer(currentDayId: 'a');
      expect(pointer.predict(0)!.label, 'A');
      expect(pointer.predict(1)!.label, 'B');
      expect(pointer.predict(2)!.label, 'C');
      // Circular: o 4º dia à frente volta ao começo do rodízio.
      expect(pointer.predict(3)!.label, 'A');
    });

    test('sem rodízio (sem plano) não projeta nada', () {
      const pointer = RotationPointer(days: []);
      expect(pointer.predict(0), isNull);
    });

    test('em dia de descanso (sem currentDayId) não projeta nada', () {
      const pointer = RotationPointer(
        days: [AgendaRotationDay(id: 'a', label: 'A')],
      );
      expect(pointer.predict(0), isNull);
    });
  });

  group('buildAgendaDays', () {
    final today = DateTime(2026, 9, 10); // quinta-feira

    test('dia com sessão sincronizada é sempre "feito"', () {
      final from = DateTime(2026, 9, 8);
      final to = DateTime(2026, 9, 9);
      final days = buildAgendaDays(
        from: from,
        to: to,
        today: today,
        sessionsByDay: {
          DateTime(2026, 9, 8): [_session(DateTime(2026, 9, 8, 7))],
        },
        pointer: _pointer(currentDayId: 'b'),
      );

      expect(days, hasLength(1));
      expect(days.single.state, AgendaDayState.done);
      expect(days.single.dayLabel, 'A');
      expect(days.single.totalSets, 6);
      expect(days.single.totalVolumeKg, 300);
    });

    test('dia passado sem sessão é descanso, nunca previsto', () {
      final days = buildAgendaDays(
        from: DateTime(2026, 9, 7),
        to: DateTime(2026, 9, 8),
        today: today,
        sessionsByDay: const {},
        pointer: _pointer(currentDayId: 'a'),
      );

      expect(days.single.state, AgendaDayState.rest);
    });

    test('hoje e dias futuros sem sessão usam a projeção da rotação', () {
      final days = buildAgendaDays(
        from: today,
        to: today.add(const Duration(days: 3)),
        today: today,
        sessionsByDay: const {},
        pointer: _pointer(currentDayId: 'b'),
      );

      expect(days.map((d) => d.state), everyElement(AgendaDayState.predicted));
      expect(days[0].dayLabel, 'B'); // hoje
      expect(days[1].dayLabel, 'C'); // amanhã
      expect(days[2].dayLabel, 'A'); // depois de amanhã (circular)
    });
  });
}
