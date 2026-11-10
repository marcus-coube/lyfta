import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/realtime/comms_socket_provider.dart';
import '../data/chat_event.dart';
import '../data/chat_repository.dart';
import '../domain/message.dart';
import 'conversations_controller.dart';

const _uuid = Uuid();

/// Histórico + rascunhos de envio de uma conversa aberta (P3.5 §1).
class ChatConversationState {
  const ChatConversationState({
    this.items = const [],
    this.pending = const [],
    this.hasMore = false,
  });

  /// Confirmadas pelo servidor, mais recente primeiro (mesma ordem do
  /// cursor keyset do P3.2).
  final List<ChatMessage> items;

  /// Enviadas por esta tela e ainda não confirmadas — mais recente por
  /// último (ordem de envio). Somem assim que o `POST` responde.
  final List<PendingMessage> pending;

  final bool hasMore;

  ChatConversationState copyWith({
    List<ChatMessage>? items,
    List<PendingMessage>? pending,
    bool? hasMore,
  }) {
    return ChatConversationState(
      items: items ?? this.items,
      pending: pending ?? this.pending,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

/// Controller de uma conversa (P3.2 REST + P3.5 UI): histórico paginado,
/// envio otimista (texto/imagem), leitura automática ao abrir/ao chegar
/// mensagem nova, e reconciliação com o WS (`chat_socket.dart`) — que só
/// entrega quente, a verdade é sempre o `ChatRepository` (REST).
class ChatMessagesController
    extends AutoDisposeFamilyAsyncNotifier<ChatConversationState, String> {
  String? _cursor;
  StreamSubscription<Map<String, dynamic>>? _eventSub;
  StreamSubscription<void>? _reconnectSub;

  @override
  Future<ChatConversationState> build(String conversationId) async {
    final socket = ref.watch(commsSocketProvider);
    _eventSub = socket.events.listen((json) {
      final event = ChatEvent.fromJson(json);
      if (event != null) _onEvent(event);
    });
    // Reconexão depois de queda (Aceite do P3.2): a tela pode ter perdido
    // eventos enquanto o WS estava fora — recarrega do zero via REST.
    _reconnectSub = socket.onReconnected.listen((_) => unawaited(refresh()));
    ref.onDispose(() {
      _eventSub?.cancel();
      _reconnectSub?.cancel();
    });

    final repo = ref.read(chatRepositoryProvider);
    final page = await repo.listMessages(conversationId, limit: 40);
    _cursor = page.nextCursor;
    unawaited(_markRead());
    return ChatConversationState(items: page.items, hasMore: page.hasMore);
  }

  void _onEvent(ChatEvent event) {
    if (event is MessageNewEvent && event.conversationId == arg) {
      _onIncoming(event.message);
    } else if (event is MessageReadEvent && event.conversationId == arg) {
      _onRead(event.messageIds);
    }
  }

  void _onIncoming(ChatMessage message) {
    final current = state.valueOrNull;
    if (current == null) return;
    // A própria mensagem enviada já chega pela resposta do POST — o WS
    // entrega de novo (publica para os dois participantes, ver Notas de
    // execução do P3.2). Sem o dedupe por id ela apareceria duas vezes.
    if (current.items.any((m) => m.id == message.id)) return;
    state = AsyncData(
      current.copyWith(items: [message, ...current.items]),
    );
    unawaited(_markRead());
  }

  void _onRead(List<String> ids) {
    final current = state.valueOrNull;
    if (current == null || ids.isEmpty) return;
    final idSet = ids.toSet();
    final now = DateTime.now();
    state = AsyncData(
      current.copyWith(
        items: [
          for (final m in current.items)
            idSet.contains(m.id) ? m.copyWith(readAt: now) : m,
        ],
      ),
    );
  }

  Future<void> _markRead() async {
    try {
      final marked = await ref.read(chatRepositoryProvider).markRead(arg);
      if (marked > 0) ref.invalidate(conversationsProvider);
    } catch (_) {
      // Marcar como lida é conforto (some o badge) — falhar aqui não pode
      // impedir a tela de mostrar o histórico já carregado.
    }
  }

  /// Mais mensagens antigas (scroll para cima) — apenas confirmadas, o
  /// histórico do servidor.
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore) return;
    final page = await ref
        .read(chatRepositoryProvider)
        .listMessages(arg, cursor: _cursor, limit: 40);
    _cursor = page.nextCursor;
    state = AsyncData(
      current.copyWith(
        items: [...current.items, ...page.items],
        hasMore: page.hasMore,
      ),
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// Envio otimista de texto (P3.5 §1): aparece na tela imediatamente,
  /// marcado como "enviando", e some assim que o `POST` confirma.
  Future<void> sendText(String senderId, String body) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    final localId = _uuid.v7();
    _addPending(
      PendingMessage(
        localId: localId,
        type: MessageType.text,
        senderId: senderId,
        body: trimmed,
        createdAt: DateTime.now(),
      ),
    );
    try {
      final message =
          await ref.read(chatRepositoryProvider).sendText(arg, trimmed);
      _resolvePending(localId, message);
    } catch (_) {
      _failPending(localId);
    }
  }

  /// Envio de imagem: presign → PUT no storage → `POST .../messages` (mesmo
  /// contrato de 3 etapas do P1.2/P2.4), com o mesmo estado otimista do
  /// texto — a prévia local (bytes) aparece na hora, a URL definitiva vem
  /// só depois de tudo confirmado.
  Future<void> sendImage({
    required String senderId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final localId = _uuid.v7();
    _addPending(
      PendingMessage(
        localId: localId,
        type: MessageType.image,
        senderId: senderId,
        imageBytes: bytes,
        createdAt: DateTime.now(),
      ),
    );
    try {
      final repo = ref.read(chatRepositoryProvider);
      final target = await repo.presignImage(
        arg,
        contentType: contentType,
        sizeBytes: bytes.length,
      );
      await repo.uploadImageBytes(target, bytes);
      final message = await repo.sendImage(arg, target.key);
      _resolvePending(localId, message);
    } catch (_) {
      _failPending(localId);
    }
  }

  /// Tenta de novo um envio que falhou — chat não tem fila offline (ADR-003
  /// §1 restringe offline à execução de treino), então uma falha de rede
  /// aqui só se resolve com o usuário pedindo de novo.
  Future<void> retry(String localId) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final failed =
        current.pending.where((p) => p.localId == localId).firstOrNull;
    if (failed == null) return;
    _updatePending(localId, failed.copyWith(status: PendingStatus.sending));
    try {
      final repo = ref.read(chatRepositoryProvider);
      final ChatMessage message;
      if (failed.type == MessageType.text) {
        message = await repo.sendText(arg, failed.body);
      } else {
        final bytes = failed.imageBytes!;
        final target = await repo.presignImage(
          arg,
          contentType: 'image/jpeg',
          sizeBytes: bytes.length,
        );
        await repo.uploadImageBytes(target, bytes);
        message = await repo.sendImage(arg, target.key);
      }
      _resolvePending(localId, message);
    } catch (_) {
      _failPending(localId);
    }
  }

  void discardFailed(String localId) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        pending: current.pending.where((p) => p.localId != localId).toList(),
      ),
    );
  }

  void _addPending(PendingMessage message) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(pending: [...current.pending, message]),
    );
  }

  void _updatePending(String localId, PendingMessage replacement) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        pending: [
          for (final p in current.pending)
            if (p.localId == localId) replacement else p,
        ],
      ),
    );
  }

  void _resolvePending(String localId, ChatMessage confirmed) {
    final current = state.valueOrNull;
    if (current == null) return;
    final alreadyThere = current.items.any((m) => m.id == confirmed.id);
    state = AsyncData(
      current.copyWith(
        items: alreadyThere ? current.items : [confirmed, ...current.items],
        pending: current.pending.where((p) => p.localId != localId).toList(),
      ),
    );
  }

  void _failPending(String localId) {
    final current = state.valueOrNull;
    if (current == null) return;
    final target =
        current.pending.where((p) => p.localId == localId).firstOrNull;
    if (target == null) return;
    _updatePending(localId, target.copyWith(status: PendingStatus.failed));
  }
}

final chatMessagesProvider = AsyncNotifierProvider.autoDispose
    .family<ChatMessagesController, ChatConversationState, String>(
  ChatMessagesController.new,
);
