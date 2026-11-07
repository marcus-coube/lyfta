import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/ly_error_state.dart';
import '../domain/message.dart';
import 'chat_message_controller.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/chat_skeletons.dart';
import 'widgets/message_input_bar.dart';

/// Tela de uma conversa (P3.5 §1): histórico paginado, envio otimista de
/// texto/imagem, leitura automática e reconexão de WS transparente (o
/// controller recarrega via REST sozinho — ver `ChatMessagesController`).
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({required this.conversationId, this.title, super.key});

  final String conversationId;

  /// Nome do outro participante, quando disponível (vem por `extra` da
  /// lista de conversas/alunos). Nulo quando a rota é aberta direto pela URL
  /// (recarregar a página na web) — mesmo critério do `StudentEvolutionScreen`.
  final String? title;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scrollController = ScrollController();
  bool _pickingImage = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_maybeLoadMore);
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // Lista invertida (mais recente embaixo): "carregar mais antigas" é
    // chegar perto do fim do scroll, não do início.
    if (position.pixels >= position.maxScrollExtent - 240) {
      ref.read(chatMessagesProvider(widget.conversationId).notifier).loadMore();
    }
  }

  String get _selfId => ref.read(authControllerProvider).userId ?? '';

  Future<void> _pickImage(ImageSource source) async {
    setState(() => _pickingImage = true);
    try {
      final file =
          await ImagePicker().pickImage(source: source, imageQuality: 92);
      if (file == null) return;
      final raw = await file.readAsBytes();
      final compressed = await FlutterImageCompress.compressWithList(
        raw,
        minWidth: 1280,
        minHeight: 1280,
        quality: 82,
        format: CompressFormat.jpeg,
      );
      if (!mounted) return;
      await ref
          .read(chatMessagesProvider(widget.conversationId).notifier)
          .sendImage(
            senderId: _selfId,
            bytes: compressed,
            contentType: 'image/jpeg',
          );
    } catch (_) {
      // Falha de picker/compressão não é um envio: o controller só sabe de
      // "sending"/"failed" depois de já ter bytes prontos.
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _showImageSourceSheet() async {
    final l10n = AppLocalizations.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.evolutionPhotoFromCamera),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.evolutionPhotoFromGallery),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pickImage(source);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(chatMessagesProvider(widget.conversationId));
    final selfId = _selfId;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: Text(widget.title ?? l10n.chatTitleFallback)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: state.when(
                loading: () => const ChatMessagesSkeleton(),
                error: (error, _) => LyErrorState(
                  message: describeApiError(context, error),
                  retryable: isRetryableError(error),
                  onRetry: () => ref
                      .read(
                        chatMessagesProvider(widget.conversationId).notifier,
                      )
                      .refresh(),
                ),
                data: (chat) {
                  final entries = _mergedEntries(chat);
                  if (entries.isEmpty) {
                    return Center(
                      child: Text(
                        l10n.chatEmpty,
                        style: LyType.body(c.textSecondary),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: LySpace.x4,
                      vertical: LySpace.x3,
                    ),
                    itemCount: entries.length,
                    itemBuilder: (context, index) =>
                        _buildEntry(entries[index], selfId),
                  );
                },
              ),
            ),
            MessageInputBar(
              sendingImage: _pickingImage,
              onPickImage: _showImageSourceSheet,
              onSendText: (text) => ref
                  .read(chatMessagesProvider(widget.conversationId).notifier)
                  .sendText(selfId, text),
            ),
          ],
        ),
      ),
    );
  }

  List<Object> _mergedEntries(ChatConversationState chat) {
    return [...chat.pending.reversed, ...chat.items];
  }

  Widget _buildEntry(Object entry, String selfId) {
    if (entry is PendingMessage) {
      return ChatBubble(
        isMine: true,
        timestamp: entry.createdAt,
        body: entry.body,
        imageBytes: entry.imageBytes,
        sending: entry.status == PendingStatus.sending,
        failed: entry.status == PendingStatus.failed,
        onRetry: () => ref
            .read(chatMessagesProvider(widget.conversationId).notifier)
            .retry(entry.localId),
        onDiscard: () => ref
            .read(chatMessagesProvider(widget.conversationId).notifier)
            .discardFailed(entry.localId),
      );
    }
    final message = entry as ChatMessage;
    return ChatBubble(
      isMine: message.senderId == selfId,
      timestamp: message.createdAt,
      body: message.body,
      imageUrl: message.mediaUrl.isEmpty ? null : message.mediaUrl,
      read: message.readAt != null,
    );
  }
}
