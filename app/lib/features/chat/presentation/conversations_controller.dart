import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/comms_socket_provider.dart';
import '../data/chat_event.dart';
import '../data/chat_repository.dart';
import '../domain/conversation.dart';

/// Lista de conversas do usuário autenticado (P3.2/P3.5 §1) — o coach vê uma
/// por aluno, o aluno vê a sua. Alimenta a lista do professor e o indicador
/// de não lidas no ícone da aba Chat dos dois shells.
///
/// Não é `autoDispose`: o contador de não lidas precisa sobreviver à troca
/// de aba (mesmo critério do `studentsProvider` do P1.6).
class ConversationsController extends AsyncNotifier<List<Conversation>> {
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  Future<List<Conversation>> build() async {
    final socket = ref.watch(commsSocketProvider);
    _sub = socket.events.listen((json) {
      final event = ChatEvent.fromJson(json);
      if (event is MessageNewEvent || event is MessageReadEvent) {
        unawaited(refresh());
      }
    });
    ref.onDispose(() => _sub?.cancel());
    return ref.read(chatRepositoryProvider).listConversations();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// Abre (ou recupera) a conversa com um aluno — só o coach chama isto
  /// (P3.2: `POST /v1/conversations` exige `owner`/`coach`).
  Future<Conversation> start(String studentId) async {
    final conv =
        await ref.read(chatRepositoryProvider).startConversation(studentId);
    await refresh();
    return conv;
  }
}

final conversationsProvider =
    AsyncNotifierProvider<ConversationsController, List<Conversation>>(
  ConversationsController.new,
);

/// Soma das não lidas de todas as conversas — é o número que o badge do
/// ícone da aba Chat mostra (P3.5 §1). `0` enquanto a lista ainda carrega:
/// o badge nasce escondido, não com um número errado.
final unreadTotalProvider = Provider<int>((ref) {
  final conversations = ref.watch(conversationsProvider).valueOrNull ?? const [];
  return conversations.fold<int>(0, (sum, c) => sum + c.unreadCount);
});
