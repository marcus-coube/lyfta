import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/features/workout/domain/block_runner.dart';
import 'package:lyfta/features/workout/domain/today.dart';
import 'package:lyfta/shared/domain/plan.dart';

BlockExercise _ex(String id, int sets, {int? rest}) => BlockExercise(
      exerciseId: id,
      sets: [for (var i = 0; i < sets; i++) PrescribedSet(repsMax: 10, restSeconds: rest)],
    );

List<ExerciseRun> _runs(Block b) => [
      for (final e in b.exercises) ExerciseRun(block: b, exercise: e, setNoOffset: 0),
    ];

List<String> _order(BlockRunner r) =>
    [for (final s in r.steps) '${s.exerciseId}${s.setNo}'];

void main() {
  test('superset A/B com 3 séries conduz A1 B1 A2 B2 A3 B3', () {
    final b = Block(
      blockType: BlockType.superset,
      restSeconds: 90,
      exercises: [_ex('A', 3), _ex('B', 3)],
    );
    final r = BlockRunner.fromRuns(_runs(b)).single;
    expect(_order(r), ['A1', 'B1', 'A2', 'B2', 'A3', 'B3']);
    expect(r.roundCount, 3);
    // Sem descanso dentro da rodada; descanso do bloco ao fim dela.
    expect(r.restAfter('A', 1), Duration.zero);
    expect(r.restAfter('B', 1), const Duration(seconds: 90));
    expect(r.restAfter('A', 2), Duration.zero);
    expect(r.restAfter('B', 3), const Duration(seconds: 90));
  });

  test('rest_seconds da série vale também no meio da rodada', () {
    final b = Block(
      blockType: BlockType.superset,
      restSeconds: 90,
      exercises: [_ex('A', 2, rest: 15), _ex('B', 2)],
    );
    final r = BlockRunner.fromRuns(_runs(b)).single;
    expect(r.restAfter('A', 1), const Duration(seconds: 15));
    expect(r.restAfter('B', 1), const Duration(seconds: 90));
  });

  test('circuito de 3 exercícios x 2 rodadas', () {
    final b = Block(
      blockType: BlockType.circuit,
      restSeconds: 60,
      exercises: [_ex('A', 2), _ex('B', 2), _ex('C', 2)],
    );
    final r = BlockRunner.fromRuns(_runs(b)).single;
    expect(_order(r), ['A1', 'B1', 'C1', 'A2', 'B2', 'C2']);
    expect(r.restAfter('B', 1), Duration.zero);
    expect(r.restAfter('C', 1), const Duration(seconds: 60));
    expect(r.restAfter('C', 2), const Duration(seconds: 60));
  });

  test('exercício com menos séries sai das rodadas finais', () {
    final b = Block(
      blockType: BlockType.superset,
      exercises: [_ex('A', 3), _ex('B', 2)],
    );
    final r = BlockRunner.fromRuns(_runs(b)).single;
    expect(_order(r), ['A1', 'B1', 'A2', 'B2', 'A3']);
    expect(r.restAfter('A', 3), const Duration(seconds: 60));
  });

  test('dropset encadeia as séries com o descanso curto da prescrição', () {
    final b = Block(
      blockType: BlockType.dropset,
      restSeconds: 90,
      exercises: [_ex('A', 3, rest: 10)],
    );
    final r = BlockRunner.fromRuns(_runs(b)).single;
    expect(r.isRounds, isFalse);
    expect(_order(r), ['A1', 'A2', 'A3']);
    expect(r.restAfter('A', 1), const Duration(seconds: 10));
  });

  test('straight: um runner por exercício, descanso igual ao 1.0', () {
    final b = Block(
      restSeconds: 75,
      exercises: [_ex('A', 2), _ex('B', 2, rest: 30)],
    );
    final rs = BlockRunner.fromRuns(_runs(b));
    expect(rs, hasLength(2));
    expect(rs.any((r) => r.isGrouped), isFalse);
    expect(rs[0].restAfter('A', 1), const Duration(seconds: 75));
    expect(rs[1].restAfter('B', 1), const Duration(seconds: 30));
  });

  test('current: primeiro pendente; pular um exercício não trava a condução', () {
    final b = Block(
      blockType: BlockType.superset,
      exercises: [_ex('A', 2), _ex('B', 2)],
    );
    final r = BlockRunner.fromRuns(_runs(b)).single;
    final done = <String>{};
    bool isDone(BlockStep s) => done.contains('${s.exerciseId}${s.setNo}');
    String cur() {
      final s = r.current(isDone);
      return s == null ? '-' : '${s.exerciseId}${s.setNo}';
    }

    expect(cur(), 'A1');
    done.add('B1'); // pulou A1
    expect(cur(), 'A2');
    done.addAll(['A2', 'B2']);
    expect(cur(), 'A1'); // sobrou o pulado
    done.add('A1');
    expect(cur(), '-');
  });

  test('set_no continua contínuo por exercício entre blocos', () {
    final b1 = Block(exercises: [_ex('A', 2)]);
    final b2 = Block(blockType: BlockType.superset, exercises: [_ex('A', 1), _ex('B', 1)]);
    final runs = [
      ExerciseRun(block: b1, exercise: b1.exercises[0], setNoOffset: 0),
      ExerciseRun(block: b2, exercise: b2.exercises[0], setNoOffset: 2),
      ExerciseRun(block: b2, exercise: b2.exercises[1], setNoOffset: 0),
    ];
    final rs = BlockRunner.fromRuns(runs);
    expect(rs, hasLength(2));
    expect(_order(rs[1]), ['A3', 'B1']);
  });
}
