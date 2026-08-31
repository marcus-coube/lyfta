import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/l10n/taxonomy_l10n.dart';
import '../data/exercise_repository.dart';
import '../../../shared/domain/exercise.dart';
import '../../../shared/widgets/exercise_media.dart';

/// Formulário do exercício próprio do tenant.
///
/// Três modos, todos na mesma tela porque os campos são os mesmos:
/// - **novo** ([source] nulo);
/// - **editar** um exercício do tenant;
/// - **duplicar** um global ([duplicate]) — a biblioteca global é somente
///   leitura (ADR-010 §3), então "editar" um global vira criar uma cópia.
class ExerciseFormScreen extends ConsumerStatefulWidget {
  const ExerciseFormScreen({this.source, this.duplicate = false, super.key});

  final Exercise? source;
  final bool duplicate;

  @override
  ConsumerState<ExerciseFormScreen> createState() => _ExerciseFormScreenState();
}

class _ExerciseFormScreenState extends ConsumerState<ExerciseFormScreen> {
  late final TextEditingController _name;
  late final TextEditingController _instructions;
  late String _muscle;
  late String _equipment;
  late String _level;

  String? _mediaUrl;
  ExerciseMediaType? _mediaType;
  bool _uploading = false;
  bool _saving = false;
  String? _error;

  /// Editar de verdade só acontece em exercício do tenant: global duplica.
  bool get _isEditing => widget.source != null && !widget.duplicate;

  @override
  void initState() {
    super.initState();
    final source = widget.source;
    _name = TextEditingController(text: source?.name ?? '');
    _instructions = TextEditingController(text: source?.instructions ?? '');
    _muscle = source?.primaryMuscle ?? ExerciseTaxonomy.muscles.first;
    _equipment = source?.equipment ?? ExerciseTaxonomy.equipment.first;
    _level = source?.level ?? ExerciseTaxonomy.levels.first;
    _mediaUrl = source?.mediaUrl;
    _mediaType = source?.mediaType;
  }

  @override
  void dispose() {
    _name.dispose();
    _instructions.dispose();
    super.dispose();
  }

  /// Escolhe o arquivo e sobe pela URL presignada (P1.2).
  ///
  /// `withData: true` porque o tamanho entra na assinatura: a URL só aceita
  /// exatamente o arquivo anunciado, então os bytes precisam estar em mãos
  /// antes de pedi-la.
  Future<void> _pickMedia() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gif', 'mp4', 'webm'],
      withData: true,
    );
    final file = result?.files.singleOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;

    final contentType = _contentTypeFor(file.extension);
    if (contentType == null) {
      setState(() => _error = AppLocalizations.of(context).errorUnsupportedMedia);
      return;
    }

    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final target = await ref
          .read(exerciseRepositoryProvider)
          .uploadMedia(bytes: bytes, contentType: contentType);
      if (!mounted) return;
      setState(() {
        _mediaUrl = target.mediaUrl;
        _mediaType = target.mediaType;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = describeApiError(context, error));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  static String? _contentTypeFor(String? extension) => switch (extension) {
        'gif' => 'image/gif',
        'mp4' => 'video/mp4',
        'webm' => 'video/webm',
        _ => null,
      };

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.exerciseFormNameRequired);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = ref.read(exerciseRepositoryProvider);
      if (_isEditing) {
        await repository.update(
          id: widget.source!.id,
          name: name,
          primaryMuscle: _muscle,
          equipment: _equipment,
          level: _level,
          instructions: _instructions.text.trim(),
          mediaUrl: _mediaUrl,
          mediaType: _mediaType,
        );
      } else {
        await repository.create(
          name: name,
          primaryMuscle: _muscle,
          equipment: _equipment,
          level: _level,
          instructions: _instructions.text.trim(),
          mediaUrl: _mediaUrl,
          mediaType: _mediaType,
        );
      }
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

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Text(
          _isEditing
              ? l10n.exerciseFormEditTitle
              : widget.duplicate
                  ? l10n.exerciseFormDuplicateTitle
                  : l10n.exerciseFormNewTitle,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(LySpace.x4),
          children: [
            if (widget.duplicate)
              Padding(
                padding: const EdgeInsets.only(bottom: LySpace.x4),
                child: Text(
                  l10n.exerciseFormDuplicateHint,
                  style: LyType.bodySm(c.textSecondary),
                ),
              ),
            LyTextField(
              label: l10n.exerciseFormNameLabel,
              hint: l10n.exerciseFormNameHint,
              controller: _name,
            ),
            const SizedBox(height: LySpace.x4),
            _TaxonomyPicker(
              label: l10n.exerciseFormMuscleLabel,
              value: _muscle,
              options: ExerciseTaxonomy.muscles,
              optionLabel: (code) => muscleLabel(l10n, code),
              onChanged: (code) => setState(() => _muscle = code),
            ),
            const SizedBox(height: LySpace.x4),
            _TaxonomyPicker(
              label: l10n.exerciseFormEquipmentLabel,
              value: _equipment,
              options: ExerciseTaxonomy.equipment,
              optionLabel: (code) => equipmentLabel(l10n, code),
              onChanged: (code) => setState(() => _equipment = code),
            ),
            const SizedBox(height: LySpace.x4),
            _TaxonomyPicker(
              label: l10n.exerciseFormLevelLabel,
              value: _level,
              options: ExerciseTaxonomy.levels,
              optionLabel: (code) => levelLabel(l10n, code),
              onChanged: (code) => setState(() => _level = code),
            ),
            const SizedBox(height: LySpace.x4),
            LyTextField(
              label: l10n.exerciseFormInstructionsLabel,
              hint: l10n.exerciseFormInstructionsHint,
              controller: _instructions,
            ),
            const SizedBox(height: LySpace.x6),
            _MediaField(
              mediaUrl: _mediaUrl,
              mediaType: _mediaType,
              uploading: _uploading,
              onPick: _pickMedia,
              onClear: () => setState(() {
                _mediaUrl = null;
                _mediaType = null;
              }),
            ),
            if (_error != null) ...[
              const SizedBox(height: LySpace.x4),
              Text(_error!, style: LyType.bodySm(c.danger)),
            ],
            const SizedBox(height: LySpace.x6),
            LyButton(
              label: l10n.commonSave,
              loading: _saving,
              onPressed: _uploading ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

/// Seletor de um código da taxonomia, com o rótulo traduzido.
class _TaxonomyPicker extends StatelessWidget {
  const _TaxonomyPicker({
    required this.label,
    required this.value,
    required this.options,
    required this.optionLabel,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final String Function(String code) optionLabel;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: LyType.label(c.textSecondary)),
        const SizedBox(height: LySpace.x2),
        DropdownButtonFormField<String>(
          initialValue: value,
          items: [
            for (final code in options)
              DropdownMenuItem(value: code, child: Text(optionLabel(code))),
          ],
          onChanged: (code) {
            if (code != null) onChanged(code);
          },
        ),
      ],
    );
  }
}

/// Campo de mídia: mostra a prévia do que já subiu e o botão de trocar.
class _MediaField extends StatelessWidget {
  const _MediaField({
    required this.mediaUrl,
    required this.mediaType,
    required this.uploading,
    required this.onPick,
    required this.onClear,
  });

  final String? mediaUrl;
  final ExerciseMediaType? mediaType;
  final bool uploading;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final hasMedia = (mediaUrl ?? '').isNotEmpty && mediaType != null;

    return LyCard(
      padding: const EdgeInsets.all(LySpace.x4),
      child: Row(
        children: [
          if (hasMedia)
            ExerciseMedia(
              exercise: Exercise(
                id: '',
                name: '',
                primaryMuscle: '',
                equipment: '',
                level: '',
                isGlobal: false,
                status: 'active',
                mediaUrl: mediaUrl,
                mediaType: mediaType,
              ),
              size: 72,
            )
          else
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: c.surfaceElevated,
                borderRadius: LyRadius.md,
              ),
              child: Icon(Icons.movie_outlined, color: c.textSecondary),
            ),
          const SizedBox(width: LySpace.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.exerciseFormMediaLabel, style: LyType.label(c.textPrimary)),
                const SizedBox(height: LySpace.x1),
                Text(l10n.exerciseFormMediaHint, style: LyType.caption(c.textSecondary)),
                const SizedBox(height: LySpace.x2),
                Row(
                  children: [
                    LyButton(
                      label: hasMedia
                          ? l10n.exerciseFormMediaReplace
                          : l10n.exerciseFormMediaPick,
                      variant: LyButtonVariant.secondary,
                      expanded: false,
                      loading: uploading,
                      onPressed: uploading ? null : onPick,
                    ),
                    if (hasMedia) ...[
                      const SizedBox(width: LySpace.x2),
                      LyButton(
                        label: l10n.commonRemove,
                        variant: LyButtonVariant.ghost,
                        expanded: false,
                        onPressed: uploading ? null : onClear,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
