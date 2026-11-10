import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/domain/plan.dart';
import '../../../shared/widgets/ly_error_state.dart';
import '../../../shared/widgets/ly_skeleton.dart';
import '../../builder/data/plan_repository.dart';
import '../../templates/data/template_repository.dart';
import '../../templates/presentation/apply_template_dialog.dart';
import 'students_controller.dart';

/// Planos do aluno (`GET /v1/students/{id}/plans`).
final studentPlansProvider =
    FutureProvider.autoDispose.family<List<PlanSummary>, String>((ref, id) {
  return ref.watch(planRepositoryProvider).byStudent(id);
});

/// Aba Treino da ficha: os planos do aluno, com o plano em uso destacado.
/// Abrir no builder, criar, aplicar modelo (P6.3), duplicar, arquivar e ativar.
/// Plano arquivado é somente leitura: abre em modo leitura e só volta por
/// "Ativar" (ou vira cópia por "Duplicar").
class StudentPlansTab extends ConsumerWidget {
  const StudentPlansTab({required this.studentId, super.key});

  final String studentId;

  Future<String?> _askTitle(BuildContext context, String initial) {
    // Seleção no texto todo: o campo já vem preenchido com o título padrão e,
    // sem isso, digitar **soma** ao default em vez de trocá-lo — foi assim que
    // o E2E do P1.8 criou um plano chamado "Workout A/BPlano E2E ABC".
    final controller = TextEditingController.fromValue(
      TextEditingValue(
        text: initial,
        selection: TextSelection(baseOffset: 0, extentOffset: initial.length),
      ),
    );
    final l10n = AppLocalizations.of(context);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.studentsNewPlanTitle),
        // Column mínimo: o LyTextField sozinho esticava o diálogo até a
        // altura da tela (E2E P4.4).
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LyTextField(
              label: l10n.studentsPlanTitleLabel,
              controller: controller,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              final value = controller.text.trim();
              Navigator.of(context).pop(value.isEmpty ? null : value);
            },
            child: Text(l10n.commonCreate),
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref, String planId) async {
    await context.push<void>('/plans/$planId');
    // Voltar do builder pode ter publicado ou mudado o plano ativo.
    ref.invalidate(studentPlansProvider(studentId));
    ref.read(studentsProvider.notifier).refresh();
  }

  /// Cria o plano e já abre o builder: criar um plano vazio e voltar para a
  /// lista não serve para nada.
  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final title = await _askTitle(context, l10n.studentsNewPlanDefaultTitle);
    if (title == null || !context.mounted) return;

    try {
      final plan = await ref
          .read(planRepositoryProvider)
          .create(studentId: studentId, title: title);
      if (!context.mounted) return;
      await _open(context, ref, plan.id);
    } catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(describeApiError(context, error))),
      );
    }
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(studentPlansProvider(studentId));
    ref.read(studentsProvider.notifier).refresh();
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
  }) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: const Key('plan_confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _applyTemplate(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showApplyTemplateDialog(context);
    if (choice == null || !context.mounted) return;
    try {
      final items = await ref.read(templateRepositoryProvider).assign(
            choice.template.id,
            studentIds: [studentId],
            publish: choice.publish,
          );
      if (!context.mounted) return;
      final item = items.isEmpty ? null : items.first;
      if (item == null || !item.ok) {
        _toast(
          context,
          item?.error?.message(l10n) ?? l10n.errorInternal,
        );
        return;
      }
      _refresh(ref);
      _toast(
        context,
        choice.publish ? l10n.applyModelApplied : l10n.applyModelAppliedDraft,
      );
    } catch (error) {
      if (!context.mounted) return;
      _toast(context, describeApiError(context, error));
    }
  }

  Future<void> _duplicate(
    BuildContext context,
    WidgetRef ref,
    PlanSummary plan,
  ) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(planRepositoryProvider).duplicate(plan.id);
      if (!context.mounted) return;
      _refresh(ref);
      _toast(context, l10n.planDuplicated);
    } catch (error) {
      if (!context.mounted) return;
      _toast(context, describeApiError(context, error));
    }
  }

  Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    PlanSummary plan,
  ) async {
    final l10n = AppLocalizations.of(context);
    final ok = await _confirm(
      context,
      title: l10n.planArchiveTitle,
      body: plan.publishedVersionNo > 0
          ? l10n.planArchiveBody
          : l10n.planArchiveDraftBody,
      action: l10n.planArchive,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(planRepositoryProvider).archive(plan.id);
      if (!context.mounted) return;
      _refresh(ref);
      _toast(context, l10n.planArchived);
    } catch (error) {
      if (!context.mounted) return;
      _toast(context, describeApiError(context, error));
    }
  }

  Future<void> _activate(
    BuildContext context,
    WidgetRef ref,
    PlanSummary plan,
  ) async {
    final l10n = AppLocalizations.of(context);
    final ok = await _confirm(
      context,
      title: l10n.planActivateTitle,
      body: l10n.planActivateBody,
      action: l10n.planActivate,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref
          .read(planRepositoryProvider)
          .activate(studentId: studentId, planId: plan.id);
      if (!context.mounted) return;
      _refresh(ref);
      _toast(context, l10n.planActivated);
    } catch (error) {
      if (!context.mounted) return;
      _toast(context, describeApiError(context, error));
    }
  }

  /// Override do próximo dia da rotação (P6.4): o coach escolhe, entre os dias
  /// da versão em uso, qual o aluno treina a seguir.
  Future<void> _nextDay(
    BuildContext context,
    WidgetRef ref,
    PlanSummary plan,
  ) async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(planRepositoryProvider);
    try {
      // A versão em uso é a última publicada (publicar já a põe na rotação);
      // o `next_day_id` só vem quando o plano é o ativo do aluno.
      final loaded =
          await repo.byId(plan.id, version: '${plan.publishedVersionNo}');
      if (!context.mounted) return;
      final dayId = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(l10n.planNextDayTitle),
          children: [
            for (final day in loaded.days)
              SimpleDialogOption(
                key: Key('next_day_${day.id}'),
                onPressed: () => Navigator.of(context).pop(day.id),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        day.title.isEmpty
                            ? day.label
                            : '${day.label} · ${day.title}',
                      ),
                    ),
                    if (day.id == loaded.nextDayId)
                      Text(
                        l10n.planNextDayCurrent,
                        style: LyType.caption(context.ly.accent),
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
      if (dayId == null || !context.mounted) return;
      await repo.setNextDay(studentId: studentId, dayId: dayId);
      if (!context.mounted) return;
      final label = loaded.days.firstWhere((d) => d.id == dayId).label;
      _refresh(ref);
      _toast(context, l10n.planNextDaySet(label));
    } catch (error) {
      if (!context.mounted) return;
      _toast(context, describeApiError(context, error));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final plans = ref.watch(studentPlansProvider(studentId));

    return plans.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(LySpace.x4),
        child: Column(
          children: [
            LySkeletonListTile(),
            SizedBox(height: LySpace.x3),
            LySkeletonListTile(),
          ],
        ),
      ),
      error: (error, _) => LyErrorState(
        message: describeApiError(context, error),
        retryable: isRetryableError(error),
        onRetry: () => ref.invalidate(studentPlansProvider(studentId)),
      ),
      data: (items) => ListView(
        padding: const EdgeInsets.all(LySpace.x4),
        children: [
          Wrap(
            spacing: LySpace.x3,
            runSpacing: LySpace.x2,
            children: [
              LyButton(
                label: l10n.studentsNewPlan,
                variant: LyButtonVariant.secondary,
                expanded: false,
                onPressed: () => _create(context, ref),
              ),
              LyButton(
                key: const Key('plans_apply_template'),
                label: l10n.planApplyTemplate,
                variant: LyButtonVariant.secondary,
                expanded: false,
                onPressed: () => _applyTemplate(context, ref),
              ),
            ],
          ),
          const SizedBox(height: LySpace.x4),
          if (items.isEmpty)
            Text(
              l10n.studentWorkoutEmpty,
              style: LyType.body(c.textSecondary),
            ),
          // Em uso primeiro, arquivados por último (a ordem do servidor vale
          // dentro de cada grupo).
          for (final plan in [
            ...items.where((p) => p.isActive),
            ...items.where((p) => !p.isActive && !p.isArchived),
            ...items.where((p) => !p.isActive && p.isArchived),
          ]) ...[
            _PlanCard(
              plan: plan,
              onOpen: () => _open(context, ref, plan.id),
              onDuplicate: () => _duplicate(context, ref, plan),
              onArchive: () => _archive(context, ref, plan),
              onActivate: () => _activate(context, ref, plan),
              onNextDay: () => _nextDay(context, ref, plan),
            ),
            const SizedBox(height: LySpace.x2),
          ],
        ],
      ),
    );
  }
}

enum _PlanAction { open, duplicate, archive, activate, nextDay }

/// Cartão de um plano: o em uso ganha borda de destaque e a etiqueta "Em uso";
/// o arquivado fica esmaecido e só oferece Ativar (se já foi publicado) e
/// Duplicar.
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.onOpen,
    required this.onDuplicate,
    required this.onArchive,
    required this.onActivate,
    required this.onNextDay,
  });

  final PlanSummary plan;
  final VoidCallback onOpen;
  final VoidCallback onDuplicate;
  final VoidCallback onArchive;
  final VoidCallback onActivate;
  final VoidCallback onNextDay;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    final card = Opacity(
      opacity: plan.isArchived ? 0.65 : 1,
      child: LyCard(
        key: Key('plan_card_${plan.id}'),
        padding: const EdgeInsets.all(LySpace.x4),
        onTap: onOpen,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.title,
                    style: LyType.label(c.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: LySpace.x1),
                  Text(
                    [
                      plan.publishedVersionNo == 0
                          ? l10n.studentWorkoutDraft
                          : l10n.studentWorkoutVersion(plan.publishedVersionNo),
                      if (plan.isActive) l10n.studentWorkoutInUse,
                      if (plan.isArchived) l10n.studentWorkoutArchived,
                      if (plan.sourceTemplateId != null)
                        l10n.studentWorkoutFromTemplate,
                    ].join(' · '),
                    style: LyType.caption(
                      plan.isActive ? c.accent : c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<_PlanAction>(
              key: Key('plan_menu_${plan.id}'),
              icon: Icon(Icons.more_vert, color: c.textSecondary),
              onSelected: (action) => switch (action) {
                _PlanAction.open => onOpen(),
                _PlanAction.duplicate => onDuplicate(),
                _PlanAction.archive => onArchive(),
                _PlanAction.activate => onActivate(),
                _PlanAction.nextDay => onNextDay(),
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _PlanAction.open,
                  child: Text(
                    plan.isArchived ? l10n.planView : l10n.planEdit,
                  ),
                ),
                // Ativar só quem já foi publicado: arquivado nunca publicado
                // não reativa (422) — o caminho é duplicar.
                if (!plan.isActive && plan.publishedVersionNo > 0)
                  PopupMenuItem(
                    value: _PlanAction.activate,
                    child: Text(l10n.planActivate),
                  ),
                // Só o plano em uso tem rotação para ajustar.
                if (plan.isActive && plan.publishedVersionNo > 0)
                  PopupMenuItem(
                    value: _PlanAction.nextDay,
                    child: Text(l10n.planNextDay),
                  ),
                PopupMenuItem(
                  value: _PlanAction.duplicate,
                  child: Text(l10n.planDuplicate),
                ),
                // O plano em uso não se arquiva: ative outro antes.
                if (!plan.isActive && !plan.isArchived)
                  PopupMenuItem(
                    value: _PlanAction.archive,
                    child: Text(l10n.planArchive),
                  ),
              ],
            ),
          ],
        ),
      ),
    );

    if (!plan.isActive) return card;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: LyRadius.lg,
        border: Border.all(color: c.accent, width: 2),
      ),
      child: card,
    );
  }
}
