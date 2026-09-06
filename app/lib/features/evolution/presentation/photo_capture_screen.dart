import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../domain/evolution_scope.dart';
import '../domain/progress_photo.dart';
import '../widgets/evolution_date_field.dart';
import '../widgets/pose_label.dart';
import 'photos_controller.dart';

/// Tela de captura de foto de evolução (P2.4 §3): câmera ou galeria,
/// compressão antes do upload (`flutter_image_compress`), pose e data.
///
/// A compressão sempre produz JPEG — o `content_type` do presign nunca
/// depende do formato original escolhido no picker, então não precisa
/// inspecionar a extensão do arquivo de origem.
class PhotoCaptureScreen extends ConsumerStatefulWidget {
  const PhotoCaptureScreen({super.key, required this.scope});

  final EvolutionScope scope;

  @override
  ConsumerState<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends ConsumerState<PhotoCaptureScreen> {
  static const _contentType = 'image/jpeg';

  Uint8List? _bytes;
  Pose _pose = Pose.front;
  DateTime _takenAt = DateTime.now();
  final _notes = TextEditingController();
  bool _picking = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    setState(() {
      _picking = true;
      _error = null;
    });
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
      setState(() => _bytes = compressed);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = AppLocalizations.of(context).evolutionPhotoPickError,
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final bytes = _bytes;
    if (bytes == null) {
      setState(() => _error = l10n.evolutionPhotoRequired);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(photosProvider(widget.scope).notifier).upload(
            bytes: bytes,
            contentType: _contentType,
            takenAt: _takenAt,
            pose: _pose,
            notes: _notes.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = describeApiError(context, error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final busy = _picking || _saving;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: Text(l10n.evolutionNewPhoto)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(LySpace.x4),
          children: [
            _PreviewBox(bytes: _bytes, loading: _picking),
            const SizedBox(height: LySpace.x3),
            Row(
              children: [
                Expanded(
                  child: LyButton(
                    label: l10n.evolutionPhotoFromCamera,
                    variant: LyButtonVariant.secondary,
                    icon: const Icon(Icons.photo_camera_outlined),
                    onPressed: busy ? null : () => _pick(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: LySpace.x3),
                Expanded(
                  child: LyButton(
                    label: l10n.evolutionPhotoFromGallery,
                    variant: LyButtonVariant.secondary,
                    icon: const Icon(Icons.photo_library_outlined),
                    onPressed: busy ? null : () => _pick(ImageSource.gallery),
                  ),
                ),
              ],
            ),
            const SizedBox(height: LySpace.x6),
            EvolutionDateField(
              label: l10n.evolutionDateLabel,
              value: _takenAt,
              onChanged: (date) => setState(() => _takenAt = date),
            ),
            const SizedBox(height: LySpace.x4),
            _PoseSelector(
              value: _pose,
              onChanged: (pose) => setState(() => _pose = pose),
            ),
            const SizedBox(height: LySpace.x4),
            LyTextField(label: l10n.evolutionNotesLabel, controller: _notes),
            if (_error != null) ...[
              const SizedBox(height: LySpace.x3),
              Text(_error!, style: LyType.bodySm(c.danger)),
            ],
            const SizedBox(height: LySpace.x6),
            LyButton(
              label: l10n.commonSave,
              loading: _saving,
              onPressed: busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewBox extends StatelessWidget {
  const _PreviewBox({required this.bytes, required this.loading});

  final Uint8List? bytes;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return AspectRatio(
      aspectRatio: 3 / 4,
      child: ClipRRect(
        borderRadius: LyRadius.lg,
        child: Container(
          color: c.surfaceElevated,
          alignment: Alignment.center,
          child: loading
              ? const CircularProgressIndicator()
              : bytes == null
                  ? Text(
                      l10n.evolutionPhotoEmptyPreview,
                      style: LyType.bodySm(c.textSecondary),
                    )
                  : Image.memory(bytes!, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class _PoseSelector extends StatelessWidget {
  const _PoseSelector({required this.value, required this.onChanged});

  final Pose value;
  final ValueChanged<Pose> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SegmentedButton<Pose>(
      segments: [
        for (final pose in Pose.values)
          ButtonSegment(value: pose, label: Text(poseLabel(l10n, pose))),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}
