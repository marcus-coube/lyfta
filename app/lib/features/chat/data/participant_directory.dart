import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/http/providers.dart';
import '../domain/conversation.dart';
import '../presentation/conversations_controller.dart';

/// Teto de ids por consulta ao diretório do `identity`.
const int participantDirectoryChunk = 100;

/// Resolve nomes por id no `identity` (`GET /v1/users/directory?ids=`).
class ParticipantDirectoryRepository {
  ParticipantDirectoryRepository(this._dio);

  final Dio _dio;

  /// Nome de cada id conhecido no tenant, em lotes de
  /// [participantDirectoryChunk]; ids que o servidor não conhece ficam de fora.
  Future<Map<String, String>> names(Iterable<String> ids) async {
    final unique = ids.toSet().toList();
    final directory = <String, String>{};
    for (var i = 0; i < unique.length; i += participantDirectoryChunk) {
      final chunk = unique.sublist(
        i,
        (i + participantDirectoryChunk).clamp(0, unique.length),
      );
      final response = await _dio.get<Map<String, dynamic>>(
        '/v1/users/directory',
        queryParameters: {'ids': chunk.join(',')},
      );
      for (final raw in response.data?['items'] as List<dynamic>? ?? const []) {
        final user = raw as Map<String, dynamic>;
        directory[user['id'] as String] = user['name'] as String? ?? '';
      }
    }
    return directory;
  }
}

final participantDirectoryRepositoryProvider =
    Provider<ParticipantDirectoryRepository>((ref) {
  return ParticipantDirectoryRepository(
    ref.watch(identityApiClientProvider).dio,
  );
});

/// Nome de cada participante das conversas do usuário, por id — o `comms` só
/// guarda ids (ADR-013 §2: nenhum serviço lê o banco do outro), então quem é o
/// outro participante só o `identity` sabe.
///
/// Busca sob demanda, pelos ids que as conversas realmente têm, em vez de
/// listar os usuários do tenant: funciona com qualquer número de alunos e o
/// aluno não precisa listar a equipe. Só refaz quando o *conjunto* de
/// participantes muda (uma mensagem nova recarrega as conversas, mas não
/// dispara nova busca).
final participantDirectoryProvider =
    FutureProvider<Map<String, String>>((ref) async {
  final selfId = ref.watch(authControllerProvider).userId ?? '';
  final key = ref.watch(
    conversationsProvider.select((async) {
      final ids = <String>{
        for (final c in async.valueOrNull ?? const <Conversation>[]) ...[
          c.studentId,
          c.coachId,
        ],
      }..remove(selfId);
      return (ids.toList()..sort()).join(',');
    }),
  );
  if (key.isEmpty) return const {};
  return ref
      .watch(participantDirectoryRepositoryProvider)
      .names(key.split(','));
});
