import '../../../shared/domain/plan.dart';
import 'today.dart';

/// Um passo da condução: uma série de um exercício do bloco.
class BlockStep {
  const BlockStep({
    required this.run,
    required this.setIndex,
    required this.round,
  });

  final ExerciseRun run;

  /// Índice (0-based) da série dentro da aparição do exercício.
  final int setIndex;

  /// Rodada (0-based). Em bloco sequencial é sempre 0.
  final int round;

  String get exerciseId => run.exerciseId;
  int get setNo => run.setNoAt(setIndex);
}

/// Condução de um bloco (P6.5): em que ordem as séries são feitas e quanto se
/// descansa depois de cada uma. Classe pura — sem widget, sem relógio.
///
/// A ordem muda, o **contrato não**: cada passo continua sendo o evento por
/// série (`exercise_id` + `set_no`) do ADR-003.
///
/// - `superset`/`circuit`: por **rodada** (série 1 de A → série 1 de B → … →
///   rodada 2). Entre exercícios da mesma rodada só há descanso se a série o
///   prescreve; ao fim da rodada vale o da série ou, na falta, o do bloco.
/// - `dropset`/`rest_pause`: exercício a exercício, séries encadeadas, com o
///   descanso curto da prescrição.
/// - `straight`: um exercício por runner, idêntico ao 1.0.
class BlockRunner {
  BlockRunner._(this.block, this.runs, this.steps);

  /// Quebra o dia achatado em runners: um por exercício no straight, um por
  /// bloco nos demais tipos.
  static List<BlockRunner> fromRuns(List<ExerciseRun> runs) {
    final out = <BlockRunner>[];
    var i = 0;
    while (i < runs.length) {
      final block = runs[i].block;
      if (block.blockType == BlockType.straight) {
        out.add(BlockRunner._build(block, [runs[i]]));
        i++;
        continue;
      }
      final group = <ExerciseRun>[];
      while (i < runs.length && identical(runs[i].block, block)) {
        group.add(runs[i]);
        i++;
      }
      out.add(BlockRunner._build(block, group));
    }
    return out;
  }

  factory BlockRunner._build(Block block, List<ExerciseRun> runs) {
    final steps = <BlockStep>[];
    final byRound = block.blockType == BlockType.superset ||
        block.blockType == BlockType.circuit;
    if (byRound) {
      var rounds = 0;
      for (final r in runs) {
        if (r.exercise.sets.length > rounds) rounds = r.exercise.sets.length;
      }
      for (var round = 0; round < rounds; round++) {
        for (final r in runs) {
          if (round < r.exercise.sets.length) {
            steps.add(BlockStep(run: r, setIndex: round, round: round));
          }
        }
      }
    } else {
      for (final r in runs) {
        for (var s = 0; s < r.exercise.sets.length; s++) {
          steps.add(BlockStep(run: r, setIndex: s, round: 0));
        }
      }
    }
    return BlockRunner._(block, runs, steps);
  }

  final Block block;
  final List<ExerciseRun> runs;
  final List<BlockStep> steps;

  BlockType get type => block.blockType;

  /// Conduzido por rodadas (superset e circuito).
  bool get isRounds =>
      type == BlockType.superset || type == BlockType.circuit;

  /// Os blocos que viram um cartão único; o straight segue um cartão por
  /// exercício, como no 1.0.
  bool get isGrouped => type != BlockType.straight;

  int get roundCount {
    var n = 0;
    for (final s in steps) {
      if (s.round + 1 > n) n = s.round + 1;
    }
    return n;
  }

  int _indexOf(String exerciseId, int setNo) => steps.indexWhere(
        (s) => s.exerciseId == exerciseId && s.setNo == setNo,
      );

  /// Descanso depois de concluir a série [exerciseId]/[setNo].
  Duration restAfter(String exerciseId, int setNo) {
    final idx = _indexOf(exerciseId, setNo);
    if (idx < 0) return Duration.zero;
    final step = steps[idx];
    if (!isRounds) return step.run.restAt(step.setIndex);

    final prescribed = step.run.exercise.sets[step.setIndex].restSeconds;
    final endsRound =
        idx + 1 >= steps.length || steps[idx + 1].round != step.round;
    if (endsRound) return step.run.restAt(step.setIndex);
    return Duration(seconds: prescribed ?? 0);
  }

  /// Passo seguinte ao que acabou de ser feito (o que o timer de descanso
  /// anuncia), ou null no fim do bloco.
  BlockStep? stepAfter(String exerciseId, int setNo, {bool Function(BlockStep)? isDone}) {
    final idx = _indexOf(exerciseId, setNo);
    if (idx < 0) return null;
    for (var i = idx + 1; i < steps.length; i++) {
      if (isDone == null || !isDone(steps[i])) return steps[i];
    }
    return null;
  }

  /// O passo da vez: o primeiro ainda não feito **depois** da última série
  /// registrada na ordem de condução; se não houver, o primeiro pendente.
  /// Assim pular um exercício (registrar B1 sem A1) leva a condução para A2 em
  /// vez de travar em A1, e corrigir uma série antiga não a move.
  BlockStep? current(bool Function(BlockStep) isDone) {
    var last = -1;
    for (var i = 0; i < steps.length; i++) {
      if (isDone(steps[i])) last = i;
    }
    for (var i = last + 1; i < steps.length; i++) {
      if (!isDone(steps[i])) return steps[i];
    }
    for (final s in steps) {
      if (!isDone(s)) return s;
    }
    return null;
  }
}
