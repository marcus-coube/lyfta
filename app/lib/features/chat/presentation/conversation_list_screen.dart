import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/ly_error_state.dart';
import '../data/participant_directory.dart';
import '../domain/conversation.dart';
import '../domain/message.dart';
import 'conversations_controller.dart';
import 'widgets/chat_skeletons.dart';

/// Lista de conversas (P3.5 §1) — o coach vê uma por aluno; um aluno com
/// mais de um professor também cai aqui (o caso comum dele, um professor só,
/// vai direto para a conversa — ver `ChatHomeScreen`).
class ConversationListScreen extends ConsumerWidget {
  const ConversationListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final conversations = ref.watch(conversationsProvider);
    final selfId = ref.watch(authControllerProvider).userId ?? '';
    final directory = ref.watch(participantDirectoryProvider).valueOrNull ?? const {};

    return conversations.when(
      loading: () => const ConversationListSkeleton(),
      error: (error, _) => LyErrorState(
        message: describeApiError(context, error),
        onRetry: () => ref.read(conversationsProvider.notifier).refresh(),
      ),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Text(l10n.chatConversationsEmpty, style: LyType.body(c.textSecondary)),
          );
        }
        return RefreshIndicator(
          onRefresh: () => ref.read(conversationsProvider.notifier).refresh(),
          child: ListView.separated(
            padding: const EdgeInsets.all(LySpace.x4),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: LySpace.x2),
            itemBuilder: (context, index) {
              final conversation = items[index];
              final otherId = conversation.otherParticipant(selfId);
              final name = directory[otherId] ?? otherId;
              return _ConversationTile(
                conversation: conversation,
                displayName: name,
                onTap: () => context.push<void>(
                  '/chat/${conversation.id}',
                  extra: name,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.displayName,
    required this.onTap,
  });

  final Conversation conversation;
  final String displayName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final last = conversation.lastMessage;
    final unread = conversation.unreadCount;

    return LyCard(
      padding: const EdgeInsets.all(LySpace.x4),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: LyType.label(c.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: LySpace.x1),
                Text(
                  _previewText(l10n, last),
                  style: LyType.caption(c.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (unread > 0) ...[
            const SizedBox(width: LySpace.x2),
            _UnreadBadge(count: unread),
          ],
        ],
      ),
    );
  }

  String _previewText(AppLocalizations l10n, ChatMessage? last) {
    if (last == null) return l10n.chatNoMessagesYet;
    return last.type == MessageType.image
        ? l10n.chatImagePreview
        : last.body;
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: LySpace.x2, vertical: 2),
      decoration: BoxDecoration(color: c.accent, borderRadius: LyRadius.pill),
      child: Text(
        count > 99 ? '99+' : count.toString(),
        style: LyType.caption(c.onAccent),
      ),
    );
  }
}
