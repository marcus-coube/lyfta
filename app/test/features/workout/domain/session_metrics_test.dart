import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/features/workout/domain/session_metrics.dart';
import 'package:lyfta/features/workout/domain/workout_event.dart';

LocalSetLog _log(
  String id,
  int setNo,
  int? reps,
  double? load, {
  String? revises,
}) =>
    LocalSetLog(
      clientId: id,
      sessionClientId: 's',
      exerciseId: 'e',
      setNo: setNo,
      performedAt: DateTime(2026),
      repsDone: reps,
      loadKg: load,
      revises: revises,
    );

void main() {
  final start = DateTime(2026, 11, 13, 10);

  test('soma séries, reps e volume; duração é fim menos início', () {
    final m = SessionMetrics.of(
      [_log('a', 1, 10, 40), _log('b', 2, 8, 42.5), _log('c', 3, null, null)],
      startedAt: start,
      endedAt: start.add(const Duration(hours: 1, minutes: 5, seconds: 9)),
    );
    expect(m.sets, 3);
    expect(m.reps, 18);
    expect(m.volumeKg, 40 * 10 + 42.5 * 8);
    expect(m.duration, const Duration(hours: 1, minutes: 5, seconds: 9));
  });

  test('revisão de série substitui o log original, sem contar duas vezes', () {
    final m = SessionMetrics.of(
      [
        _log('a', 1, 10, 40),
        _log('b', 2, 10, 40),
        // Corrige a série 1: 10x40 vira 8x45.
        _log('a2', 1, 8, 45, revises: 'a'),
      ],
      startedAt: start,
      endedAt: start,
    );
    expect(m.sets, 2);
    expect(m.reps, 18);
    expect(m.volumeKg, 40 * 10 + 8 * 45);
  });

  test('revisão de revisão: só o último elo da cadeia vale', () {
    final m = SessionMetrics.of(
      [
        _log('a', 1, 10, 40),
        _log('a2', 1, 9, 40, revises: 'a'),
        _log('a3', 1, 8, 40, revises: 'a2'),
      ],
      startedAt: start,
      endedAt: start,
    );
    expect(m.sets, 1);
    expect(m.reps, 8);
  });

  test('lista já com revisões aplicadas dá o mesmo resultado', () {
    final m = SessionMetrics.of(
      [_log('b', 2, 10, 40), _log('a2', 1, 8, 45, revises: 'a')],
      startedAt: start,
      endedAt: start,
    );
    expect(m.sets, 2);
    expect(m.volumeKg, 400 + 360);
  });

  test('relógio atrasado não gera duração negativa', () {
    final m = SessionMetrics.of(
      const [],
      startedAt: start,
      endedAt: start.subtract(const Duration(seconds: 5)),
    );
    expect(m.duration, Duration.zero);
    expect(m.sets, 0);
  });

  test('formatClock usa h:mm:ss', () {
    expect(formatClock(Duration.zero), '0:00:00');
    expect(formatClock(const Duration(minutes: 5, seconds: 7)), '0:05:07');
    expect(
      formatClock(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
    expect(formatClock(const Duration(hours: 12)), '12:00:00');
  });
}
