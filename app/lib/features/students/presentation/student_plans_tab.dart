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
import 'students_controller.dart';

/// Planos do aluno (`GET /v1/students/{id}/plans`).
final studentPlansProvider =
    FutureProvider.autoDispose.family<List<PlanSummary>, String>((ref, id) {
  return ref.watch(planRepositoryProvider).byStudent(id);
});

/// Aba Treino da ficha: os planos do aluno, abrir no builder e criar um
/// novo. É o que a lista de alunos fazia no P1.6 antes de virar gestão; a P6
/// amplia esta aba (modelos, duplicar, histórico).
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
          Align(
            alignment: Alignment.centerLeft,
            child: LyButton(
              label: l10n.studentsNewPlan,
              variant: LyButtonVariant.secondary,
              expanded: false,
              onPressed: () => _create(context, ref),
            ),
          ),
          const SizedBox(height: LySpace.x4),
          if (items.isEmpty)
            Text(
              l10n.studentWorkoutEmpty,
              style: LyType.body(c.textSecondary),
            ),
          for (final plan in items) ...[
            LyCard(
              padding: const EdgeInsets.all(LySpace.x4),
              onTap: () => _open(context, ref, plan.id),
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
                                : l10n.studentWorkoutVersion(
                                    plan.publishedVersionNo,
                                  ),
                            if (plan.isActive) l10n.studentWorkoutInUse,
                          ].join(' · '),
                          style: LyType.caption(c.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: c.textSecondary),
                ],
              ),
            ),
            const SizedBox(height: LySpace.x2),
          ],
        ],
      ),
    );
  }
}
