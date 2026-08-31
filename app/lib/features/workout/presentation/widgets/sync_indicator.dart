import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/l10n/gen/app_localizations.dart';
import '../../data/sync_worker.dart';

/// Indicador discreto do estado da fila offline (ADR-003 §4).
///
/// O aluno precisa saber que o treino dele **não se perdeu** quando registrou
/// tudo em modo avião — sem que isso vire um alarme no meio do treino.
class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final sync = ref.watch(syncWorkerProvider);

    final (IconData icon, String label, Color color) = switch (sync) {
      SyncState(syncing: true) => (
          Icons.sync,
          l10n.todaySyncing,
          c.textSecondary
        ),
      SyncState(pending: final pending) when pending > 0 => (
          Icons.cloud_upload_outlined,
          l10n.todaySyncPending(pending),
          c.warning
        ),
      _ => (Icons.cloud_done_outlined, l10n.todaySynced, c.textSecondary),
    };

    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: LySpace.x2),
        Text(label, style: LyType.caption(color)),
      ],
    );
  }
}
