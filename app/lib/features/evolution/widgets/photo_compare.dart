import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../domain/progress_photo.dart';
import 'pose_label.dart';

/// Comparador antes/depois (P2.4 §3): duas fotos lado a lado com seletor de
/// data para cada lado. [items] vem na ordem que o `assessment` devolve
/// (mais recente primeiro) — o comparador começa com a mais antiga à
/// esquerda e a mais recente à direita, o par mais informativo por padrão.
class PhotoCompare extends StatefulWidget {
  const PhotoCompare({required this.items, super.key});

  final List<ProgressPhoto> items;

  @override
  State<PhotoCompare> createState() => _PhotoCompareState();
}

class _PhotoCompareState extends State<PhotoCompare> {
  // Guardado por id, não pela instância: a lista de [items] é substituída
  // inteira a cada `refresh()` do controller (nova foto, exclusão), e um
  // `DropdownButtonFormField` cujo `value` não é `identical` a nenhum item
  // da lista nova quebra a asserção do widget.
  String? _beforeId;
  String? _afterId;

  @override
  void didUpdateWidget(covariant PhotoCompare oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureDefaults();
  }

  @override
  void initState() {
    super.initState();
    _ensureDefaults();
  }

  void _ensureDefaults() {
    if (widget.items.isEmpty) return;
    _beforeId ??= widget.items.last.id;
    _afterId ??= widget.items.first.id;
  }

  ProgressPhoto? _find(String? id) {
    if (id == null) return null;
    for (final photo in widget.items) {
      if (photo.id == id) return photo;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ly;

    if (widget.items.length < 2) {
      return Text(
        l10n.evolutionPhotosCompareNeedTwo,
        style: LyType.body(c.textSecondary),
      );
    }

    final before = _find(_beforeId) ?? widget.items.last;
    final after = _find(_afterId) ?? widget.items.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _DateDropdown(
                items: widget.items,
                value: before,
                onChanged: (photo) => setState(() => _beforeId = photo?.id),
              ),
            ),
            const SizedBox(width: LySpace.x3),
            Expanded(
              child: _DateDropdown(
                items: widget.items,
                value: after,
                onChanged: (photo) => setState(() => _afterId = photo?.id),
              ),
            ),
          ],
        ),
        const SizedBox(height: LySpace.x3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _ComparePane(photo: before)),
            const SizedBox(width: LySpace.x3),
            Expanded(child: _ComparePane(photo: after)),
          ],
        ),
      ],
    );
  }
}

class _DateDropdown extends StatelessWidget {
  const _DateDropdown({
    required this.items,
    required this.value,
    required this.onChanged,
  });

  final List<ProgressPhoto> items;
  final ProgressPhoto? value;
  final ValueChanged<ProgressPhoto?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final format = DateFormat.yMMMd(locale);

    return DropdownButtonFormField<ProgressPhoto>(
      initialValue: value,
      isExpanded: true,
      items: [
        for (final photo in items)
          DropdownMenuItem(
            value: photo,
            child: Text(
              '${format.format(photo.takenAt)} · ${poseLabel(l10n, photo.pose)}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _ComparePane extends StatelessWidget {
  const _ComparePane({required this.photo});

  final ProgressPhoto photo;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;

    return AspectRatio(
      aspectRatio: 3 / 4,
      child: ClipRRect(
        borderRadius: LyRadius.md,
        child: CachedNetworkImage(
          imageUrl: photo.mediaUrl,
          fit: BoxFit.cover,
          placeholder: (context, _) => ColoredBox(color: c.surfaceElevated),
          errorWidget: (context, _, __) => ColoredBox(
            color: c.surfaceElevated,
            child: Icon(Icons.broken_image_outlined, color: c.textSecondary),
          ),
        ),
      ),
    );
  }
}
