import 'dart:convert';

/// Tipos de evento da fila offline (ADR-003 §2, contrato do P1.5).
enum WorkoutEventType {
  sessionStart('session_start'),
  setLog('set_log'),
  sessionFinish('session_finish'),
  setRevision('set_revision');

  const WorkoutEventType(this.code);

  final String code;

  static WorkoutEventType fromCode(String code) =>
      WorkoutEventType.values.firstWhere((t) => t.code == code);
}

/// Um fato da execução, gerado no device e despachado depois.
///
/// O [clientId] é a chave de idempotência do ADR-003: o servidor casa o
/// reenvio por ele, então o mesmo evento pode ir para a rede quantas vezes
/// for preciso sem duplicar nada.
class WorkoutEvent {
  const WorkoutEvent({
    required this.clientId,
    required this.type,
    required this.performedAt,
    required this.payload,
  });

  final String clientId;
  final WorkoutEventType type;
  final DateTime performedAt;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {
        'client_id': clientId,
        'type': type.code,
        // O servidor faz sanidade de relógio (ADR-003): sempre UTC.
        'performed_at': performedAt.toUtc().toIso8601String(),
        'payload': payload,
      };

  String encodePayload() => jsonEncode(payload);
}

/// Desfecho de um evento no lote (`accepted` | `duplicate` | `rejected`).
///
/// `rejected` sai da fila junto com os aceitos: um evento que o servidor
/// recusa por conteúdo nunca vai ser aceito numa retentativa, e mantê-lo na
/// fila travaria o device para sempre. Só erro de **rede** preserva a fila.
class SyncOutcome {
  const SyncOutcome({required this.clientId, required this.status, this.code});

  factory SyncOutcome.fromJson(Map<String, dynamic> json) {
    return SyncOutcome(
      clientId: json['client_id'] as String? ?? '',
      status: json['status'] as String? ?? 'rejected',
      code: json['code'] as String?,
    );
  }

  final String clientId;
  final String status;
  final String? code;

  bool get isRejected => status == 'rejected';
}

/// Resposta de `POST /v1/sync/workout-logs`.
class SyncResult {
  const SyncResult({
    required this.outcomes,
    required this.accepted,
    required this.duplicates,
    required this.rejected,
    this.nextDayLabel,
  });

  factory SyncResult.fromJson(Map<String, dynamic> json) {
    final state = json['state'] as Map<String, dynamic>?;
    return SyncResult(
      outcomes: (json['results'] as List<dynamic>? ?? const [])
          .map((raw) => SyncOutcome.fromJson(raw as Map<String, dynamic>))
          .toList(),
      accepted: json['accepted'] as int? ?? 0,
      duplicates: json['duplicates'] as int? ?? 0,
      rejected: json['rejected'] as int? ?? 0,
      nextDayLabel: state?['next_day_label'] as String?,
    );
  }

  final List<SyncOutcome> outcomes;
  final int accepted;
  final int duplicates;
  final int rejected;

  /// Rótulo do próximo dia depois do lote — é assim que o app sabe que o
  /// treino virou B sem outra chamada (ADR-004 §3).
  final String? nextDayLabel;
}

/// Sessão de treino em andamento no device. Vira `workout_sessions` no
/// servidor quando o `session_start` da fila for aceito.
class LocalSession {
  const LocalSession({
    required this.clientId,
    required this.dayId,
    required this.dayLabel,
    required this.dayTitle,
    required this.startedAt,
    this.finishedAt,
  });

  final String clientId;
  final String dayId;
  final String dayLabel;
  final String dayTitle;
  final DateTime startedAt;
  final DateTime? finishedAt;

  bool get isOpen => finishedAt == null;
}

/// Uma série registrada no device — fato imutável (ADR-003 §2). Corrigir não
/// edita: cria outro log com [revises] apontando para o [clientId] do errado.
class LocalSetLog {
  const LocalSetLog({
    required this.clientId,
    required this.sessionClientId,
    required this.exerciseId,
    required this.setNo,
    required this.performedAt,
    this.repsDone,
    this.loadKg,
    this.rpe,
    this.revises,
  });

  final String clientId;
  final String sessionClientId;
  final String exerciseId;
  final int setNo;
  final DateTime performedAt;
  final int? repsDone;
  final double? loadKg;
  final double? rpe;
  final String? revises;

  /// Volume da série (carga × reps) — o resumo do fim do treino soma isto.
  double get volumeKg => (loadKg ?? 0) * (repsDone ?? 0);
}
