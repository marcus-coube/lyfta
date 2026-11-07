import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/ly_error_state.dart';
import '../data/participant_directory.dart';
import 'chat_screen.dart';
import 'conversation_list_screen.dart';
import 'conversations_controller.dart';
import 'widgets/chat_skeletons.dart';

/// Conteúdo da aba Chat de cada shell (P3.5 §1): o coach sempre vê a lista
/// de conversas (uma por aluno); o aluno, no caso comum de ter um só
/// professor, cai direto na conversa — só vira lista se ele tiver mais de um
/// vínculo (também cobre "ainda sem conversa nenhuma", com um estado vazio).
class ChatHomeScreen extends ConsumerWidget {
  const ChatHomeScreen({required this.isCoach, super.key});

  final bool isCoach;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isCoach) return const ConversationListScreen();

    final conversations = ref.watch(conversationsProvider);

    return conversations.when(
      loading: () => const ConversationListSkeleton(),
      error: (error, _) => LyErrorState(
        message: describeApiError(context, error),
        retryable: isRetryableError(error),
        onRetry: () => ref.read(conversationsProvider.notifier).refresh(),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const _StartWithCoach();
        }
        if (items.length > 1) return const ConversationListScreen();

        final directory =
            ref.watch(participantDirectoryProvider).valueOrNull ?? const {};
        final conversation = items.first;
        final name = directory[conversation.coachId];
        return ChatScreen(conversationId: conversation.id, title: name);
      },
    );
  }
}

/// Estado vazio do aluno: ele mesmo abre a conversa com o professor
/// vinculado (ADR-016). Sem professor, o servidor responde `no_coach`.
class _StartWithCoach extends ConsumerStatefulWidget {
  const _StartWithCoach();

  @override
  ConsumerState<_StartWithCoach> createState() => _StartWithCoachState();
}

class _StartWithCoachState extends ConsumerState<_StartWithCoach> {
  bool _busy = false;
  String? _error;

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(conversationsProvider.notifier).startWithMyCoach();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = describeApiError(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LySpace.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.chatStudentNoConversation,
              textAlign: TextAlign.center,
              style: LyType.body(c.textSecondary),
            ),
            const SizedBox(height: LySpace.x4),
            LyButton(
              label: l10n.chatStudentStart,
              expanded: false,
              loading: _busy,
              onPressed: _busy ? null : _start,
            ),
            if (_error != null) ...[
              const SizedBox(height: LySpace.x3),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: LyType.bodySm(c.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
