/// Limites de uma série registrada — espelham a validação do sync no
/// `workout` (`maxReps` e `maxTargetValue` em `internal/http/plans.go`).
///
/// O app precisa barrar antes: evento rejeitado pelo servidor sai da fila
/// sem aviso (ADR-003), e uma correção encadeada nele cai junto
/// (`unknown_revised_log`) — o aparelho e o servidor divergem calados
/// (achado A9 do E2E 2.0).
const maxSetReps = 1000;
const maxSetLoadKg = 1000.0;

/// O que o aluno digitou numa série, já interpretado. Campo vazio é válido
/// (nulo: não informado); texto que não vira número ou passa do limite não.
class SetInput {
  const SetInput._({
    required this.reps,
    required this.load,
    required this.repsInvalid,
    required this.loadInvalid,
  });

  /// Aceita vírgula ou ponto como separador decimal da carga (ADR-011 §4).
  factory SetInput.parse({required String reps, required String load}) {
    final repsText = reps.trim();
    final loadText = load.trim().replaceAll(',', '.');
    final parsedReps = repsText.isEmpty ? null : int.tryParse(repsText);
    final parsedLoad = loadText.isEmpty ? null : double.tryParse(loadText);
    return SetInput._(
      reps: parsedReps,
      load: parsedLoad,
      repsInvalid: repsText.isNotEmpty &&
          (parsedReps == null || parsedReps < 0 || parsedReps > maxSetReps),
      loadInvalid: loadText.isNotEmpty &&
          (parsedLoad == null ||
              parsedLoad.isNaN ||
              parsedLoad < 0 ||
              parsedLoad > maxSetLoadKg),
    );
  }

  final int? reps;
  final double? load;
  final bool repsInvalid;
  final bool loadInvalid;

  bool get isValid => !repsInvalid && !loadInvalid;
}
