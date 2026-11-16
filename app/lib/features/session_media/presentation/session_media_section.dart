import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../domain/session_media.dart';
import 'send_media_sheet.dart';
import 'session_media_controller.dart';

/// Botão "Enviar vídeo ao professor" do cartão do exercício (P12.2 §1).
class SessionMediaButton extends StatelessWidget {
  const SessionMediaButton({
    super.key,
    required this.sessionClientId,
    required this.exerciseId,
    required this.exerciseName,
  });

  final String sessionClientId;
  final String exerciseId;
  final String exerciseName;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: ValueKey('media-action-$exerciseId'),
      tooltip: AppLocalizations.of(context).sessionMediaAction,
      icon: const Icon(Icons.videocam_outlined),
      onPressed: () => showSendMediaSheet(
        context,
        sessionClientId: sessionClientId,
        exerciseId: exerciseId,
        exerciseName: exerciseName,
      ),
    );
  }
}

/// "Enviados neste treino" (P12.2 §6): o envio em curso (progresso, cancelar,
/// tentar de novo) e o que já subiu (estado, expiração, remover).
class SessionMediaSection extends ConsumerWidget {
  const SessionMediaSection({super.key, required this.sessionClientId});

  final String sessionClientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(sessionMediaProvider(sessionClientId));
    final upload = state.upload;
    if (state.items.isEmpty && upload == null) return const SizedBox.shrink();

    return Column(
      key: const Key('session-media-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.sessionMediaListTitle, style: LyType.title(c.textPrimary)),
        const SizedBox(height: LySpace.x2),
        for (final item in state.items)
          _MediaRow(sessionClientId: sessionClientId, item: item),
        if (upload != null)
          _UploadRow(sessionClientId: sessionClientId, upload: upload),
      ],
    );
  }
}

class _MediaRow extends ConsumerWidget {
  const _MediaRow({required this.sessionClientId, required this.item});

  final String sessionClientId;
  final SessionMedia item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final date = DateFormat.Md(Localizations.localeOf(context).toString())
        .format(item.deleteAfter);
    final status = item.isExpired
        ? l10n.sessionMediaStatusExpired
        : item.isSeen
            ? l10n.sessionMediaStatusSeen(date)
            : l10n.sessionMediaStatusSent(date);

    return ListTile(
      key: ValueKey('media-${item.id}'),
      contentPadding: EdgeInsets.zero,
      leading: _Thumb(item: item),
      title: Text(
        item.exerciseName ?? l10n.sessionMediaWholeWorkout,
        style: LyType.body(c.textPrimary),
      ),
      subtitle: Text(
        status,
        key: ValueKey('media-status-${item.id}'),
        style: LyType.bodySm(c.textSecondary),
      ),
      trailing: item.isExpired
          ? null
          : IconButton(
              key: ValueKey('media-remove-${item.id}'),
              tooltip: l10n.sessionMediaRemove,
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await ref
                      .read(sessionMediaProvider(sessionClientId).notifier)
                      .remove(item.id);
                } catch (error) {
                  if (!context.mounted) return;
                  messenger.showSnackBar(
                    SnackBar(content: Text(describeApiError(context, error))),
                  );
                }
              },
            ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.item});

  final SessionMedia item;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final icon = Icon(
      item.isVideo ? Icons.play_circle_outline : Icons.image_outlined,
      color: c.textSecondary,
    );
    final url = item.mediaUrl;
    return ClipRRect(
      borderRadius: LyRadius.md,
      child: SizedBox(
        width: 48,
        height: 48,
        child: ColoredBox(
          color: c.surface,
          child: item.isVideo || url == null
              ? Center(child: icon)
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(child: icon),
                ),
        ),
      ),
    );
  }
}

class _UploadRow extends ConsumerWidget {
  const _UploadRow({required this.sessionClientId, required this.upload});

  final String sessionClientId;
  final MediaUpload upload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(sessionMediaProvider(sessionClientId).notifier);

    return Padding(
      key: const Key('media-upload'),
      padding: const EdgeInsets.symmetric(vertical: LySpace.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (upload.failed)
            Text(
              describeApiError(context, upload.error!),
              key: const Key('media-upload-error'),
              style: LyType.bodySm(c.danger),
            )
          else ...[
            Text(
              l10n.sessionMediaUploading((upload.progress * 100).round()),
              style: LyType.bodySm(c.textPrimary),
            ),
            const SizedBox(height: LySpace.x1),
            LinearProgressIndicator(value: upload.progress),
          ],
          Row(
            children: [
              if (upload.failed)
                TextButton(
                  key: const Key('media-retry'),
                  onPressed: controller.retry,
                  child: Text(l10n.sessionMediaRetry),
                ),
              TextButton(
                key: const Key('media-cancel'),
                onPressed: controller.cancel,
                child: Text(
                  upload.failed
                      ? l10n.sessionMediaDiscard
                      : l10n.sessionMediaCancel,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
