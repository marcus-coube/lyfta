import 'package:flutter/widgets.dart';

import '../domain/today.dart';

/// Campos de carga das séries de **um exercício** do dia (P10.1).
///
/// Cada `SetRow` era dono do seu controller; para replicar a carga digitada
/// nas outras séries alguém que enxerga o exercício inteiro precisa segurar
/// os controllers. É estado só de tela: nada vai para o banco local nem para
/// a fila (ADR-003). Exercício repetido no dia é outro [ExerciseFields]
/// (a chave é [keyFor]).
class ExerciseFields extends ChangeNotifier {
  ExerciseFields({required this.exerciseName});

  /// Nome mostrado no diálogo; o dono atualiza a cada build.
  String exerciseName;

  final _loads = <int, TextEditingController>{};
  var _isLogged = (int setNo) => false;
  var _used = false;
  int? _offerSetNo;

  /// `setNo` + [isLogged] do estado atual da sessão. Chamado no build do dono.
  void bind({required String name, required bool Function(int setNo) isLogged}) {
    exerciseName = name;
    _isLogged = isLogged;
  }

  /// Chave do exercício no dia: o mesmo exercício em outra posição
  /// (`setNoOffset`) conta como exercício separado.
  static String keyFor(ExerciseRun run) => '${run.exerciseId}:${run.setNoOffset}';

  /// Controller da carga da série [setNo]; nasce com [initial] e sobrevive à
  /// linha sair da árvore (rolagem da lista).
  TextEditingController loadFor(int setNo, String initial) =>
      _loads.putIfAbsent(setNo, () => TextEditingController(text: initial));

  /// O aluno mexeu na carga da série [setNo]: oferece replicar se houver
  /// outra série pendente com carga diferente.
  void loadEdited(int setNo) {
    if (_used) return;
    _offerSetNo = setNo;
    notifyListeners();
  }

  /// A oferta aparece sob a linha da série [setNo] enquanto ainda faz
  /// sentido: série pendente, e ao menos uma outra pendente com carga
  /// diferente.
  bool offerFor(int setNo) {
    if (_used || _offerSetNo != setNo || _isLogged(setNo)) return false;
    return _targets(setNo).isNotEmpty;
  }

  String sourceText(int setNo) => (_loads[setNo]?.text ?? '').trim();

  List<int> _targets(int source) {
    final text = sourceText(source);
    return [
      for (final e in _loads.entries)
        if (e.key != source && !_isLogged(e.key) && e.value.text.trim() != text)
          e.key,
    ];
  }

  /// Preenche o campo de carga das demais séries pendentes. Não toca em
  /// reps nem em série registrada.
  void replicate(int setNo) {
    final text = sourceText(setNo);
    for (final t in _targets(setNo)) {
      _loads[t]!.text = text;
    }
    _used = true;
    _offerSetNo = null;
    notifyListeners();
  }

  void dismiss() {
    _used = true;
    _offerSetNo = null;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final c in _loads.values) {
      c.dispose();
    }
    super.dispose();
  }
}

/// Um [ExerciseFields] por exercício do dia, vivo durante o player.
class ExerciseFieldsRegistry {
  final _byKey = <String, ExerciseFields>{};

  ExerciseFields forRun(ExerciseRun run, String name) {
    final f = _byKey.putIfAbsent(
      ExerciseFields.keyFor(run),
      () => ExerciseFields(exerciseName: name),
    );
    return f;
  }

  void dispose() {
    for (final f in _byKey.values) {
      f.dispose();
    }
    _byKey.clear();
  }
}
