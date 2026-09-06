/// De quem é a evolução que a tela está olhando: o próprio aluno ("me",
/// resolvido pela claim do token — nenhuma rota carrega parâmetro de aluno)
/// ou um aluno específico visto pelo coach ("student", ficha do P2.5).
///
/// As duas portas de cada endpoint do P2.1/P2.3 seguem o mesmo formato nos
/// dois serviços (`workout` e `assessment`): `/v1/me/...` ou
/// `/v1/students/{id}/...`. Por isso um único prefixo resolve as chamadas
/// para os dois `Dio` do [EvolutionRepository] — dívida anotada nas Notas de
/// execução da P2.4, fechada aqui.
class EvolutionScope {
  const EvolutionScope.me() : studentId = null;

  const EvolutionScope.student(this.studentId);

  /// Nulo quando o escopo é o próprio aluno.
  final String? studentId;

  bool get isCoach => studentId != null;

  /// Prefixo comum às rotas de histórico/medidas/bioimpedância/fotos/presign
  /// nos dois serviços.
  String get basePath => isCoach ? '/v1/students/$studentId' : '/v1/me';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EvolutionScope && other.studentId == studentId);

  @override
  int get hashCode => studentId.hashCode;

  @override
  String toString() => 'EvolutionScope(${studentId ?? 'me'})';
}
