import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/ly_error_state.dart';
import '../../../shared/widgets/ly_skeleton.dart';
import '../data/template_repository.dart';
import '../domain/template.dart';
import 'template_form_dialog.dart';
import 'templates_controller.dart';

/// Aba Modelos do coach (P6.3): biblioteca de modelos do tenant com busca,
/// criar, abrir no builder (modo modelo), aplicar, ver quem recebeu e
/// arquivar/desarquivar.
class TemplatesScreen extends ConsumerStatefulWidget {
  const TemplatesScreen({super.key});

  @override
  ConsumerState<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends ConsumerState<TemplatesScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(templateQueryProvider.notifier).state = value;
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context);
    final form = await showTemplateFormDialog(
      context,
      heading: l10n.templatesNewTitle,
      withDescription: true,
    );
    if (form == null || !mounted) return;

    try {
      final plan = await ref
          .read(templateRepositoryProvider)
          .create(title: form.title, description: form.description);
      if (!mounted) return;
      await context.push<void>('/plans/${plan.id}');
      ref.read(templatesProvider.notifier).refresh();
    } catch (error) {
      if (!mounted) return;
      _toast(describeApiError(context, error));
    }
  }

  Future<void> _open(TemplateSummary template) async {
    await context.push<void>('/plans/${template.id}');
    ref.read(templatesProvider.notifier).refresh();
  }

  Future<void> _toggleArchive(TemplateSummary template) async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(templateRepositoryProvider);
    try {
      if (template.isArchived) {
        await repo.unarchive(template.id);
      } else {
        await repo.archive(template.id);
      }
      if (!mounted) return;
      ref.read(templatesProvider.notifier).refresh();
      _toast(
        template.isArchived
            ? l10n.templatesUnarchivedToast
            : l10n.templatesArchivedToast,
      );
    } catch (error) {
      if (!mounted) return;
      _toast(describeApiError(context, error));
    }
  }

  Future<void> _assign(TemplateSummary template) async {
    await context.push<void>(
      '/templates/${template.id}/assign',
      extra: template.title,
    );
    // Aplicar muda a contagem "aplicado a N alunos".
    ref.read(templatesProvider.notifier).refresh();
  }

  Future<void> _recipients(TemplateSummary template) async {
    await context.push<void>(
      '/templates/${template.id}/recipients',
      extra: template.title,
    );
    ref.read(templatesProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final templates = ref.watch(templatesProvider);
    final archived = ref.watch(templateArchivedFilterProvider);
    final filtered = ref.watch(templateQueryProvider).trim().isNotEmpty;

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LyTextField(
          label: l10n.templatesSearchLabel,
          hint: l10n.templatesSearchHint,
          controller: _search,
          prefixIcon: Icons.search,
          onChanged: _onSearchChanged,
        ),
        const SizedBox(height: LySpace.x3),
        Wrap(
          spacing: LySpace.x2,
          children: [
            ChoiceChip(
              key: const Key('templates_filter_active'),
              label: Text(l10n.templatesFilterActive),
              selected: !archived,
              onSelected: (_) => ref
                  .read(templateArchivedFilterProvider.notifier)
                  .state = false,
            ),
            ChoiceChip(
              key: const Key('templates_filter_archived'),
              label: Text(l10n.templatesFilterArchived),
              selected: archived,
              onSelected: (_) => ref
                  .read(templateArchivedFilterProvider.notifier)
                  .state = true,
            ),
          ],
        ),
      ],
    );

    return Scaffold(
      backgroundColor: c.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        icon: const Icon(Icons.add),
        label: Text(l10n.templatesNew),
      ),
      body: templates.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(LySpace.x4),
          physics: const NeverScrollableScrollPhysics(),
          children: [
            header,
            for (var i = 0; i < 4; i++) ...[
              const SizedBox(height: LySpace.x3),
              const LySkeletonListTile(),
            ],
          ],
        ),
        error: (error, _) => ListView(
          padding: const EdgeInsets.all(LySpace.x4),
          children: [
            header,
            SizedBox(
              height: 280,
              child: LyErrorState(
                message: describeApiError(context, error),
                retryable: isRetryableError(error),
                onRetry: () => ref.read(templatesProvider.notifier).refresh(),
              ),
            ),
          ],
        ),
        data: (state) => ListView(
          padding: const EdgeInsets.fromLTRB(
            LySpace.x4,
            LySpace.x4,
            LySpace.x4,
            LySpace.x16,
          ),
          children: [
            header,
            const SizedBox(height: LySpace.x3),
            if (state.items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: LySpace.x8),
                child: Text(
                  filtered
                      ? l10n.templatesEmptyFiltered
                      : archived
                          ? l10n.templatesEmptyArchived
                          : l10n.templatesEmpty,
                  textAlign: TextAlign.center,
                  style: LyType.body(c.textSecondary),
                ),
              ),
            for (final template in state.items)
              Padding(
                padding: const EdgeInsets.only(bottom: LySpace.x2),
                child: _TemplateTile(
                  template: template,
                  onOpen: () => _open(template),
                  onAssign: () => _assign(template),
                  onRecipients: () => _recipients(template),
                  onToggleArchive: () => _toggleArchive(template),
                ),
              ),
            if (state.hasMore)
              Center(
                child: state.loadingMore
                    ? const Padding(
                        padding: EdgeInsets.all(LySpace.x3),
                        child: CircularProgressIndicator(),
                      )
                    : TextButton(
                        key: const Key('templates_load_more'),
                        onPressed: () =>
                            ref.read(templatesProvider.notifier).loadMore(),
                        child: Text(
                          state.loadMoreFailed
                              ? l10n.commonRetry
                              : l10n.commonLoadMore,
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _TemplateAction { edit, assign, recipients, archive }

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.template,
    required this.onOpen,
    required this.onAssign,
    required this.onRecipients,
    required this.onToggleArchive,
  });

  final TemplateSummary template;
  final VoidCallback onOpen;
  final VoidCallback onAssign;
  final VoidCallback onRecipients;
  final VoidCallback onToggleArchive;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    final status = template.publishedVersionNo == 0
        ? l10n.studentWorkoutDraft
        : template.hasDraft
            ? '${l10n.builderPublishedVersion(template.publishedVersionNo)} · '
                '${l10n.templatesUnpublishedChanges}'
            : l10n.builderPublishedVersion(template.publishedVersionNo);

    return LyCard(
      padding: const EdgeInsets.all(LySpace.x4),
      onTap: onOpen,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  template.title,
                  style: LyType.label(c.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                if (template.description.isNotEmpty) ...[
                  const SizedBox(height: LySpace.x1),
                  Text(
                    template.description,
                    style: LyType.bodySm(c.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: LySpace.x1),
                Text(
                  [
                    status,
                    l10n.templatesDays(template.daysCount),
                    l10n.templatesExercises(template.exercisesCount),
                    template.assignedCount == 0
                        ? l10n.templatesNotAssigned
                        : l10n.templatesAssignedTo(template.assignedCount),
                  ].join(' · '),
                  style: LyType.caption(c.textSecondary),
                ),
              ],
            ),
          ),
          PopupMenuButton<_TemplateAction>(
            key: Key('template_menu_${template.id}'),
            icon: Icon(Icons.more_vert, color: c.textSecondary),
            onSelected: (action) => switch (action) {
              _TemplateAction.edit => onOpen(),
              _TemplateAction.assign => onAssign(),
              _TemplateAction.recipients => onRecipients(),
              _TemplateAction.archive => onToggleArchive(),
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _TemplateAction.edit,
                child: Text(l10n.templatesMenuEdit),
              ),
              if (template.canAssign)
                PopupMenuItem(
                  value: _TemplateAction.assign,
                  child: Text(l10n.templatesMenuAssign),
                ),
              if (template.assignedCount > 0)
                PopupMenuItem(
                  value: _TemplateAction.recipients,
                  child: Text(l10n.templatesMenuRecipients),
                ),
              PopupMenuItem(
                value: _TemplateAction.archive,
                child: Text(
                  template.isArchived
                      ? l10n.templatesMenuUnarchive
                      : l10n.templatesMenuArchive,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
