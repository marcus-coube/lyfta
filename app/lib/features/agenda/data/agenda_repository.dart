import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/agenda_session.dart';
import '../domain/rotation_pointer.dart';
import 'agenda_api.dart';

final agendaRepositoryProvider = Provider<AgendaRepository>((ref) {
  return AgendaRepository(ref.watch(agendaApiProvider));
});

/// Repositório da agenda semanal do aluno (P4.1): junta o estado da rotação
/// (P1.5) com as sessões sincronizadas por período (endpoint novo desta
/// tarefa). A projeção de "treino previsto" em si não mora aqui — é
/// `buildAgendaDays` (domain), puro e testável sem rede.
class AgendaRepository {
  AgendaRepository(this._api);

  final AgendaApi _api;

  Future<RotationPointer> rotationPointer() async {
    final json = await _api.today();
    return RotationPointer.fromTodayJson(json);
  }

  /// Sessões sincronizadas em `[from, to)`, agrupadas pela data **local** em
  /// que começaram (`started_at`). ADR-003 é explícito que relatório usa o
  /// horário que o device registrou ao abrir a sessão, não o de
  /// sincronização — sem isso, um treino feito offline no sábado e
  /// sincronizado só na segunda apareceria na segunda-feira da agenda.
  Future<Map<DateTime, List<AgendaSession>>> sessionsByDay(
    DateTime from,
    DateTime to,
  ) async {
    final raw = await _api.sessions(from: from, to: to);
    final out = <DateTime, List<AgendaSession>>{};
    for (final item in raw) {
      final session = AgendaSession.fromJson(item);
      final key = DateTime(
        session.startedAt.year,
        session.startedAt.month,
        session.startedAt.day,
      );
      (out[key] ??= <AgendaSession>[]).add(session);
    }
    return out;
  }
}
