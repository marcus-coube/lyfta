import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../domain/progress_photo.dart';
import 'pose_label.dart';

/// Grade de fotos de evolução por data/pose (P2.4 §3) — mais recente
/// primeiro, na ordem que o `assessment` já devolve.
class PhotoGrid extends StatelessWidget {
  const PhotoGrid({
    required this.items,
    this.onTap,
    super.key,
  });

  final List<ProgressPhoto> items;
  final ValueChanged<ProgressPhoto>? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ly;

    if (items.isEmpty) {
      return Text(
        l10n.evolutionPhotosEmpty,
        style: LyType.body(c.textSecondary),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: LySpace.x2,
        mainAxisSpacing: LySpace.x2,
        childAspectRatio: 0.8,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final photo = items[index];
        return _PhotoTile(
          photo: photo,
          onTap: onTap == null ? null : () => onTap!(photo),
        );
      },
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo, this.onTap});

  final ProgressPhoto photo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: LyRadius.md,
        child: ClipRRect(
          borderRadius: LyRadius.md,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: photo.mediaUrl,
                fit: BoxFit.cover,
                placeholder: (context, _) =>
                    ColoredBox(color: c.surfaceElevated),
                errorWidget: (context, _, __) => ColoredBox(
                  color: c.surfaceElevated,
                  child:
                      Icon(Icons.broken_image_outlined, color: c.textSecondary),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: LySpace.x2,
                    vertical: LySpace.x1,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.65),
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat.yMMMd(locale).format(photo.takenAt),
                        style: LyType.caption(Colors.white),
                      ),
                      Text(
                        poseLabel(l10n, photo.pose),
                        style: LyType.caption(Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
