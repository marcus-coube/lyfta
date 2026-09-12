import 'package:flutter/widgets.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../shared/widgets/ly_skeleton.dart';

/// Silhueta da lista de conversas (P4.2 §2) — usada tanto pelo coach
/// (`ConversationListScreen`) quanto pelo aluno com mais de um professor
/// (`ChatHomeScreen`), enquanto `conversationsProvider` ainda não respondeu.
class ConversationListSkeleton extends StatelessWidget {
  const ConversationListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(LySpace.x4),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: LySpace.x4),
      itemBuilder: (context, index) => const LySkeletonListTile(),
    );
  }
}

/// Silhueta da conversa aberta (P4.2 §2) — bolhas alternadas enquanto
/// `chatMessagesProvider` carrega a primeira página.
class ChatMessagesSkeleton extends StatelessWidget {
  const ChatMessagesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(LySpace.x4),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 8,
      itemBuilder: (context, index) => Align(
        alignment: index.isEven ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: LySpace.x1),
          child: LySkeletonBox(
            width: 160 + (index % 3) * 30,
            height: 36,
            borderRadius: LyRadius.lg,
          ),
        ),
      ),
    );
  }
}
