import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../account/data/account_repository.dart';
import '../../account/presentation/account_controller.dart';
import '../data/media_preparer.dart';
import '../domain/session_media.dart';
import 'session_media_controller.dart';

/// Abre a folha "Enviar ao professor" (P12.2 §1) — do cartão do exercício
/// (com [exerciseId]/[exerciseName]) ou do menu do player (sem exercício).
Future<void> showSendMediaSheet(
  BuildContext context, {
  required String sessionClientId,
  String? exerciseId,
  String? exerciseName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => SendMediaSheet(
      sessionClientId: sessionClientId,
      exerciseId: exerciseId,
      exerciseName: exerciseName,
    ),
  );
}

/// Folha de envio: aviso de retenção e limite sempre visíveis antes de
/// escolher o arquivo; sem consentimento `progress_photos` leva à Conta em vez
/// de abrir a câmera (P12.2 §5). O envio em si roda no
/// [SessionMediaController] — a folha fecha na hora e o treino segue.
class SendMediaSheet extends ConsumerStatefulWidget {
  const SendMediaSheet({
    super.key,
    required this.sessionClientId,
    this.exerciseId,
    this.exerciseName,
  });

  final String sessionClientId;
  final String? exerciseId;
  final String? exerciseName;

  @override
  ConsumerState<SendMediaSheet> createState() => _SendMediaSheetState();
}

class _SendMediaSheetState extends ConsumerState<SendMediaSheet> {
  final _note = TextEditingController();
  bool _video = true;
  bool _picking = false;
  PreparedMedia? _picked;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final media = await ref
          .read(mediaPreparerProvider)
          .pick(video: _video, source: source);
      if (!mounted || media == null) return;
      if (media.exceedsLimit) {
        setState(() {
          _picked = null;
          _error = l10n.sessionMediaTooLarge(
            _mb(media.sizeBytes),
            sessionMediaMaxBytes ~/ (1024 * 1024),
          );
        });
        return;
      }
      setState(() => _picked = media);
    } catch (_) {
      if (mounted) setState(() => _error = l10n.sessionMediaPickError);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _send() {
    final media = _picked;
    if (media == null) return;
    final note = _note.text.trim();
    // Sem `await`: o upload não prende a folha nem o registro de séries.
    unawaited(
      ref.read(sessionMediaProvider(widget.sessionClientId).notifier).start(
            media: media,
            note: note.isEmpty ? null : note,
            exerciseId: widget.exerciseId,
            exerciseName: widget.exerciseName,
          ),
    );
    Navigator.of(context).pop();
  }

  void _openPrivacy() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    unawaited(router.push('/account'));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final consent = ref.watch(consentStatusProvider);
    final media = ref.watch(sessionMediaProvider(widget.sessionClientId));

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: LySpace.x6,
          right: LySpace.x6,
          top: LySpace.x6,
          bottom: LySpace.x6 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.sessionMediaTitle, style: LyType.h2(c.textPrimary)),
            if (widget.exerciseName != null) ...[
              const SizedBox(height: LySpace.x1),
              Text(
                l10n.sessionMediaForExercise(widget.exerciseName!),
                style: LyType.bodySm(c.textSecondary),
              ),
            ],
            const SizedBox(height: LySpace.x4),
            _Notice(
              key: const Key('media-warning'),
              icon: Icons.info_outline,
              text: l10n.sessionMediaWarning,
            ),
            const SizedBox(height: LySpace.x4),
            ...consent.when(
              loading: () => const [
                Center(child: CircularProgressIndicator()),
              ],
              error: (error, _) => [
                _Notice(
                  key: const Key('media-consent-error'),
                  icon: Icons.wifi_off,
                  text: error is ApiException && error.code == 'network_error'
                      ? l10n.sessionMediaNeedsConnection
                      : describeApiError(context, error),
                ),
                const SizedBox(height: LySpace.x3),
                LyButton(
                  label: l10n.sessionMediaRetryLoad,
                  variant: LyButtonVariant.secondary,
                  onPressed: () => ref.invalidate(consentStatusProvider),
                ),
              ],
              data: (status) => !status.has(ConsentPurpose.progressPhotos)
                  ? _noConsent(l10n)
                  : media.atLimit
                      ? [
                          _Notice(
                            key: const Key('media-limit'),
                            icon: Icons.block,
                            text: l10n.sessionMediaLimitReached(
                              sessionMediaMaxPerSession,
                            ),
                          ),
                        ]
                      : _form(l10n),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _noConsent(AppLocalizations l10n) => [
        _Notice(
          key: const Key('media-no-consent'),
          icon: Icons.lock_outline,
          text: l10n.sessionMediaConsentBody,
        ),
        const SizedBox(height: LySpace.x3),
        LyButton(
          key: const Key('media-open-privacy'),
          label: l10n.sessionMediaOpenPrivacy,
          onPressed: _openPrivacy,
        ),
      ];

  List<Widget> _form(AppLocalizations l10n) {
    final c = context.ly;
    final picked = _picked;
    return [
      SegmentedButton<bool>(
        segments: [
          ButtonSegment(
            value: true,
            icon: const Icon(Icons.videocam_outlined),
            label: Text(l10n.sessionMediaKindVideo),
          ),
          ButtonSegment(
            value: false,
            icon: const Icon(Icons.photo_outlined),
            label: Text(l10n.sessionMediaKindPhoto),
          ),
        ],
        selected: {_video},
        onSelectionChanged: _picking
            ? null
            : (s) => setState(() {
                  _video = s.first;
                  _picked = null;
                  _error = null;
                }),
      ),
      const SizedBox(height: LySpace.x3),
      Row(
        children: [
          Expanded(
            child: LyButton(
              key: const Key('media-camera'),
              label: l10n.sessionMediaCamera,
              variant: LyButtonVariant.secondary,
              icon: const Icon(Icons.photo_camera_outlined),
              onPressed: _picking ? null : () => _pick(ImageSource.camera),
            ),
          ),
          const SizedBox(width: LySpace.x3),
          Expanded(
            child: LyButton(
              key: const Key('media-gallery'),
              label: l10n.sessionMediaGallery,
              variant: LyButtonVariant.secondary,
              icon: const Icon(Icons.photo_library_outlined),
              onPressed: _picking ? null : () => _pick(ImageSource.gallery),
            ),
          ),
        ],
      ),
      if (_picking) ...[
        const SizedBox(height: LySpace.x3),
        const LinearProgressIndicator(),
      ],
      if (picked != null) ...[
        const SizedBox(height: LySpace.x3),
        Text(
          l10n.sessionMediaPicked(
            picked.isVideo
                ? l10n.sessionMediaKindVideo
                : l10n.sessionMediaKindPhoto,
            _mb(picked.sizeBytes),
          ),
          key: const Key('media-picked'),
          style: LyType.bodySm(c.textPrimary),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: LySpace.x3),
        Text(
          _error!,
          key: const Key('media-error'),
          style: LyType.bodySm(c.danger),
        ),
      ],
      const SizedBox(height: LySpace.x4),
      TextField(
        key: const Key('media-note'),
        controller: _note,
        maxLength: sessionMediaNoteMaxLength,
        maxLines: 2,
        decoration: InputDecoration(labelText: l10n.sessionMediaNote),
      ),
      const SizedBox(height: LySpace.x3),
      LyButton(
        key: const Key('media-send'),
        label: l10n.sessionMediaSend,
        onPressed: picked == null || _picking ? null : _send,
      ),
    ];
  }
}

String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    return Container(
      padding: const EdgeInsets.all(LySpace.x3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: LyRadius.md,
        border: Border.all(color: c.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: c.info),
          const SizedBox(width: LySpace.x3),
          Expanded(child: Text(text, style: LyType.bodySm(c.textPrimary))),
        ],
      ),
    );
  }
}
