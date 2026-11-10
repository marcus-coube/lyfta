import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/ly_skeleton.dart';
import '../../checkin/presentation/coach_checkins_tab.dart';
import '../domain/bioimpedance.dart';
import '../domain/evolution_scope.dart';
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
import 'summary_tab.dart';

/// A aba Evolução (P2.4) e a ficha de evolução do aluno vista pelo coach
/// (P2.5) — a mesma composição, parametrizada pelo [EvolutionScope].
///
/// Seções em abas, não telas separadas: é o mesmo dado (o progresso do
/// aluno) visto de vários ângulos. No escopo do coach entra uma aba a mais,
/// o Resumo (`GET /v1/students/{id}/summary`, P2.3), que a tela do aluno não
/// tem — quem já vê as três listas inteiras não precisa do condensado.
class EvolutionScreen extends StatefulWidget {
  const EvolutionScreen({
    super.key,
    this.scope = const EvolutionScope.me(),
    this.showCheckins = true,
  });

  final EvolutionScope scope;

  /// Aba Check-ins (só no escopo do coach). A ficha do aluno (P5.4) a mostra
  /// como aba própria e passa `false` para não repeti-la aqui dentro.
  final bool showCheckins;

  bool get _hasCheckins => scope.isCoach && showCheckins;

  @override
  State<EvolutionScreen> createState() => _EvolutionScreenState();
}

class _EvolutionScreenState extends State<EvolutionScreen>
    with SingleTickerProviderStateMixin {
  // Check-ins (P3.5 §3) é mais uma aba coach-only, no mesmo espírito do
  // Resumo (P2.5): quem já vê as três listas do aluno não precisa da
  // avaliação de treino junto — só o coach.
  late final _tabController = TabController(
    length: widget.scope.isCoach ? (widget._hasCheckins ? 5 : 4) : 3,
    vsync: this,
  );

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
            isScrollable: widget.scope.isCoach,
            tabAlignment:
                widget.scope.isCoach ? TabAlignment.start : TabAlignment.fill,
            tabs: [
              if (widget.scope.isCoach) Tab(text: l10n.evolutionTabSummary),
              Tab(text: l10n.evolutionTabLoad),
              Tab(text: l10n.evolutionTabMeasurements),
              Tab(text: l10n.evolutionTabPhotos),
              if (widget._hasCheckins)
                Tab(child: CheckinsTabLabel(studentId: widget.scope.studentId!)),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              if (widget.scope.isCoach) SummaryTab(scope: widget.scope),
              _LoadTab(scope: widget.scope),
              _MeasurementsTab(scope: widget.scope),
              _PhotosTab(scope: widget.scope),
              if (widget._hasCheckins)
                CoachCheckinsTab(studentId: widget.scope.studentId!),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoadTab extends ConsumerWidget {
  const _LoadTab({required this.scope});

  final EvolutionScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logged = ref.watch(loggedExercisesProvider(scope));

    return logged.when(
      loading: () => const _LoadTabSkeleton(),
      error: (error, _) => _TabError(
        message: _describeError(context, error, scope),
        retryable: isRetryableError(error),
        onRetry: () => ref.invalidate(loggedExercisesProvider(scope)),
      ),
      data: (items) {
        final selection = ref.watch(loadSelectionProvider(scope));
        final effectiveId = selection.exerciseId ??
            (items.isEmpty ? null : items.first.exercise.id);

        return ListView(
          padding: const EdgeInsets.all(LySpace.x4),
          children: [
            ExerciseSelector(
              items: items,
              selectedId: effectiveId,
              onChanged: (id) => ref
                  .read(loadSelectionProvider(scope).notifier)
                  .update((s) => s.copyWith(exerciseId: id)),
            ),
            const SizedBox(height: LySpace.x4),
            if (effectiveId != null)
              Consumer(
                builder: (context, ref, _) {
                  final history = ref.watch(
                    exerciseHistoryProvider(
                      (
                        scope: scope,
                        exerciseId: effectiveId,
                        since: selection.range.since(DateTime.now())
                      ),
                    ),
                  );
                  return history.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: LySpace.x4),
                      child: LySkeletonBox(width: double.infinity, height: 220),
                    ),
                    error: (error, _) => _TabError(
                      message: _describeError(context, error, scope),
                      retryable: isRetryableError(error),
                      onRetry: () => ref.invalidate(
                        exerciseHistoryProvider(
                          (
                            scope: scope,
                            exerciseId: effectiveId,
                            since: selection.range.since(DateTime.now())
                          ),
                        ),
                      ),
                    ),
                    data: (points) => LoadChartPanel(
                      points: points,
                      metric: selection.metric,
                      onMetricChanged: (metric) => ref
                          .read(loadSelectionProvider(scope).notifier)
                          .update((s) => s.copyWith(metric: metric)),
                      range: selection.range,
                      onRangeChanged: (range) => ref
                          .read(loadSelectionProvider(scope).notifier)
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
  const _MeasurementsTab({required this.scope});

  final EvolutionScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final measurements = ref.watch(measurementsProvider(scope));
    final bioimpedance = ref.watch(bioimpedanceProvider(scope));

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
          loading: () => const _ListRowsSkeleton(),
          error: (error, _) => _TabError(
            message: _describeError(context, error, scope),
            retryable: isRetryableError(error),
            onRetry: () => ref.invalidate(measurementsProvider(scope)),
          ),
          data: (state) => Column(
            children: [
              MeasurementList(
                items: state.items,
                onDelete: (item) =>
                    _confirmDeleteMeasurement(context, ref, item),
              ),
              if (state.hasMore)
                _LoadMoreButton(
                  onTap: () => unawaited(
                    ref.read(measurementsProvider(scope).notifier).loadMore(),
                  ),
                ),
            ],
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
          loading: () => const _ListRowsSkeleton(),
          error: (error, _) => _TabError(
            message: _describeError(context, error, scope),
            retryable: isRetryableError(error),
            onRetry: () => ref.invalidate(bioimpedanceProvider(scope)),
          ),
          data: (state) => Column(
            children: [
              BioimpedanceList(
                items: state.items,
                onDelete: (item) =>
                    _confirmDeleteBioimpedance(context, ref, item),
              ),
              if (state.hasMore)
                _LoadMoreButton(
                  onTap: () => unawaited(
                    ref.read(bioimpedanceProvider(scope).notifier).loadMore(),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openMeasurementForm(BuildContext context) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => MeasurementFormScreen(scope: scope)),
    );
  }

  Future<void> _openBioimpedanceForm(BuildContext context) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => BioimpedanceFormScreen(scope: scope)),
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
      await ref.read(measurementsProvider(scope).notifier).delete(item.id);
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
      await ref.read(bioimpedanceProvider(scope).notifier).delete(item.id);
    }
  }
}

class _PhotosTab extends ConsumerWidget {
  const _PhotosTab({required this.scope});

  final EvolutionScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final photos = ref.watch(photosProvider(scope));

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
              MaterialPageRoute(
                builder: (_) => PhotoCaptureScreen(scope: scope),
              ),
            );
          },
        ),
        const SizedBox(height: LySpace.x3),
        photos.when(
          loading: () => const _PhotoGridSkeleton(),
          error: (error, _) => _TabError(
            message: _describeError(context, error, scope),
            retryable: isRetryableError(error),
            onRetry: () => ref.invalidate(photosProvider(scope)),
          ),
          data: (state) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PhotoGrid(
                items: state.items,
                onTap: (photo) => _openViewer(context, ref, photo),
              ),
              if (state.hasMore)
                _LoadMoreButton(
                  onTap: () => unawaited(
                    ref.read(photosProvider(scope).notifier).loadMore(),
                  ),
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
      await ref.read(photosProvider(scope).notifier).delete(photo.id);
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

/// Botão de paginação incremental (P4.2 §2) — medidas, bioimpedância e fotos
/// já vêm do servidor por cursor keyset (`evolution_repository.dart`), mas
/// os widgets "burros" (`MeasurementList`/`BioimpedanceList`/`PhotoGrid`)
/// não sabem paginar sozinhos; ficam dentro de um `ListView` maior junto de
/// outras seções, então um botão — não scroll infinito — é o gatilho mais
/// simples de "buscar a próxima página" sem competir com o scroll da aba
/// inteira.
class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: LySpace.x3),
      child: LyButton(
        label: l10n.commonLoadMore,
        variant: LyButtonVariant.secondary,
        expanded: false,
        onPressed: onTap,
      ),
    );
  }
}

/// Silhueta da aba Carga (P4.2 §2): seletor de exercício + área do gráfico.
class _LoadTabSkeleton extends StatelessWidget {
  const _LoadTabSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(LySpace.x4),
      child: Column(
        children: [
          LySkeletonLine(width: double.infinity, height: 48),
          SizedBox(height: LySpace.x4),
          LySkeletonBox(width: double.infinity, height: 220),
        ],
      ),
    );
  }
}

/// Silhueta de uma lista curta (P4.2 §2): medidas e bioimpedância são só
/// algumas linhas por vez, então um bloco fixo de 3 já preenche a área sem
/// piscar o layout quando os dados de verdade chegam.
class _ListRowsSkeleton extends StatelessWidget {
  const _ListRowsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        LySkeletonListTile(avatarSize: 40),
        SizedBox(height: LySpace.x3),
        LySkeletonListTile(avatarSize: 40),
        SizedBox(height: LySpace.x3),
        LySkeletonListTile(avatarSize: 40),
      ],
    );
  }
}

/// Silhueta da grade de fotos (P4.2 §2) — mesma proporção do `PhotoGrid`
/// (3 colunas, quadrado).
class _PhotoGridSkeleton extends StatelessWidget {
  const _PhotoGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: LySpace.x2,
      crossAxisSpacing: LySpace.x2,
      children: List.generate(
        6,
        (_) => const LySkeletonBox(
          width: double.infinity,
          height: double.infinity,
          borderRadius: LyRadius.sm,
        ),
      ),
    );
  }
}

/// Mensagem de erro das abas. Na porta do coach, `consent_required` é o
/// aluno que não autorizou dados de saúde (ADR-008 §1) — a mensagem padrão
/// fala com o titular e não serve aqui.
String _describeError(
  BuildContext context,
  Object error,
  EvolutionScope scope,
) {
  return describeScopedError(context, error, coachScope: scope.isCoach);
}

class _TabError extends StatelessWidget {
  const _TabError({
    required this.message,
    required this.onRetry,
    this.retryable = true,
  });

  final String message;
  final VoidCallback onRetry;

  /// Falso para erro que repetir não resolve (`student_not_found`, ADR-016).
  final bool retryable;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ly;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: LyType.body(c.textSecondary)),
          if (retryable) ...[
            const SizedBox(height: LySpace.x3),
            LyButton(
              label: l10n.commonRetry,
              variant: LyButtonVariant.secondary,
              expanded: false,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}
