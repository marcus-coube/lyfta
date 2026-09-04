import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../domain/bioimpedance.dart';
import '../domain/measurement.dart';
import '../domain/progress_photo.dart';
import '../widgets/bioimpedance_list.dart';
import '../widgets/exercise_selector.dart';
import '../widgets/load_chart_panel.dart';
import '../widgets/measurement_list.dart';
import '../widgets/photo_compare.dart';
import '../widgets/photo_grid.dart';
import 'bioimpedance_controller.dart';
import 'bioimpedance_form_screen.dart';
import 'load_controller.dart';
import 'measurement_form_screen.dart';
import 'measurements_controller.dart';
import 'photo_capture_screen.dart';
import 'photos_controller.dart';

/// A aba Evolução do aluno (P2.4): Carga, Medidas e Fotos.
///
/// Três seções em abas, não telas separadas — é o mesmo dado (o progresso
/// do aluno) visto de três ângulos, e o P2.5 reabre exatamente esta
/// composição na ficha do aluno pelo lado do coach.
class EvolutionScreen extends StatefulWidget {
  const EvolutionScreen({super.key});

  @override
  State<EvolutionScreen> createState() => _EvolutionScreenState();
}

class _EvolutionScreenState extends State<EvolutionScreen>
    with SingleTickerProviderStateMixin {
  late final _tabController = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        ColoredBox(
          color: c.surface,
          child: TabBar(
            controller: _tabController,
            labelColor: c.accent,
            unselectedLabelColor: c.textSecondary,
            indicatorColor: c.accent,
            tabs: [
              Tab(text: l10n.evolutionTabLoad),
              Tab(text: l10n.evolutionTabMeasurements),
              Tab(text: l10n.evolutionTabPhotos),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [_LoadTab(), _MeasurementsTab(), _PhotosTab()],
          ),
        ),
      ],
    );
  }
}

class _LoadTab extends ConsumerWidget {
  const _LoadTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final logged = ref.watch(loggedExercisesProvider);

    return logged.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _TabError(
        message: describeApiError(context, error),
        onRetry: () => ref.invalidate(loggedExercisesProvider),
      ),
      data: (items) {
        final selection = ref.watch(loadSelectionProvider);
        final effectiveId = selection.exerciseId ??
            (items.isEmpty ? null : items.first.exercise.id);

        return ListView(
          padding: const EdgeInsets.all(LySpace.x4),
          children: [
            ExerciseSelector(
              items: items,
              selectedId: effectiveId,
              onChanged: (id) => ref
                  .read(loadSelectionProvider.notifier)
                  .update((s) => s.copyWith(exerciseId: id)),
            ),
            const SizedBox(height: LySpace.x4),
            if (effectiveId != null)
              Consumer(
                builder: (context, ref, _) {
                  final history = ref.watch(
                    exerciseHistoryProvider(
                      (
                        exerciseId: effectiveId,
                        since: selection.range.since(DateTime.now())
                      ),
                    ),
                  );
                  return history.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: LySpace.x8),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, _) => Text(
                      describeApiError(context, error),
                      style: LyType.bodySm(c.danger),
                    ),
                    data: (points) => LoadChartPanel(
                      points: points,
                      metric: selection.metric,
                      onMetricChanged: (metric) => ref
                          .read(loadSelectionProvider.notifier)
                          .update((s) => s.copyWith(metric: metric)),
                      range: selection.range,
                      onRangeChanged: (range) => ref
                          .read(loadSelectionProvider.notifier)
                          .update((s) => s.copyWith(range: range)),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

class _MeasurementsTab extends ConsumerWidget {
  const _MeasurementsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final measurements = ref.watch(measurementsProvider);
    final bioimpedance = ref.watch(bioimpedanceProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        LySpace.x4,
        LySpace.x4,
        LySpace.x4,
        LySpace.x16,
      ),
      children: [
        _SectionHeader(
          title: l10n.evolutionMeasurementsSection,
          actionLabel: l10n.evolutionAddMeasurement,
          onAction: () => _openMeasurementForm(context),
        ),
        const SizedBox(height: LySpace.x3),
        measurements.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text(
            describeApiError(context, error),
            style: LyType.bodySm(context.ly.danger),
          ),
          data: (state) => MeasurementList(
            items: state.items,
            onDelete: (item) => _confirmDeleteMeasurement(context, ref, item),
          ),
        ),
        const SizedBox(height: LySpace.x8),
        _SectionHeader(
          title: l10n.evolutionBioimpedanceSection,
          actionLabel: l10n.evolutionAddBioimpedance,
          onAction: () => _openBioimpedanceForm(context),
        ),
        const SizedBox(height: LySpace.x3),
        bioimpedance.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text(
            describeApiError(context, error),
            style: LyType.bodySm(context.ly.danger),
          ),
          data: (state) => BioimpedanceList(
            items: state.items,
            onDelete: (item) => _confirmDeleteBioimpedance(context, ref, item),
          ),
        ),
      ],
    );
  }

  Future<void> _openMeasurementForm(BuildContext context) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const MeasurementFormScreen()),
    );
  }

  Future<void> _openBioimpedanceForm(BuildContext context) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const BioimpedanceFormScreen()),
    );
  }

  Future<void> _confirmDeleteMeasurement(
    BuildContext context,
    WidgetRef ref,
    BodyMeasurement item,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.evolutionDeleteTitle),
        content: Text(l10n.evolutionDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.commonRemove),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(measurementsProvider.notifier).delete(item.id);
    }
  }

  Future<void> _confirmDeleteBioimpedance(
    BuildContext context,
    WidgetRef ref,
    BioimpedanceRecord item,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.evolutionDeleteTitle),
        content: Text(l10n.evolutionDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.commonRemove),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(bioimpedanceProvider.notifier).delete(item.id);
    }
  }
}

class _PhotosTab extends ConsumerWidget {
  const _PhotosTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final photos = ref.watch(photosProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        LySpace.x4,
        LySpace.x4,
        LySpace.x4,
        LySpace.x16,
      ),
      children: [
        _SectionHeader(
          title: l10n.evolutionPhotosSection,
          actionLabel: l10n.evolutionAddPhoto,
          onAction: () async {
            await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => const PhotoCaptureScreen()),
            );
          },
        ),
        const SizedBox(height: LySpace.x3),
        photos.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text(
            describeApiError(context, error),
            style: LyType.bodySm(context.ly.danger),
          ),
          data: (state) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PhotoGrid(
                items: state.items,
                onTap: (photo) => _openViewer(context, ref, photo),
              ),
              const SizedBox(height: LySpace.x8),
              Text(
                l10n.evolutionPhotosCompareTitle,
                style: LyType.h2(context.ly.textPrimary),
              ),
              const SizedBox(height: LySpace.x3),
              PhotoCompare(items: state.items),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openViewer(
    BuildContext context,
    WidgetRef ref,
    ProgressPhoto photo,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: SizedBox(
          width: 320,
          height: 400,
          child: Image.network(photo.mediaUrl, fit: BoxFit.contain),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.commonRemove),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(photosProvider.notifier).delete(photo.id);
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;

    return Row(
      children: [
        Expanded(child: Text(title, style: LyType.h2(c.textPrimary))),
        LyButton(
          label: actionLabel,
          variant: LyButtonVariant.secondary,
          expanded: false,
          icon: const Icon(Icons.add),
          onPressed: onAction,
        ),
      ],
    );
  }
}

class _TabError extends StatelessWidget {
  const _TabError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ly;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: LyType.body(c.textSecondary)),
          const SizedBox(height: LySpace.x3),
          LyButton(
            label: l10n.commonRetry,
            variant: LyButtonVariant.secondary,
            expanded: false,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
