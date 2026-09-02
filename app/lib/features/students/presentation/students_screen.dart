import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../builder/data/plan_repository.dart';
import 'students_controller.dart';

/// Lista de alunos do professor (P1.6): quem está na academia, qual plano
/// cada um está fazendo e o caminho para montar o próximo.
class StudentsScreen extends ConsumerStatefulWidget {
  const StudentsScreen({super.key});

  @override
  ConsumerState<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends ConsumerState<StudentsScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openPlan(String planId) async {
    await context.push<void>('/plans/$planId');
    if (!mounted) return;
    // Voltar do builder pode ter mudado o plano ativo do aluno.
    ref.read(studentsProvider.notifier).refresh();
  }

  /// Cria o plano e já abre o builder: criar um plano vazio e voltar para a
  /// lista não serve para nada.
  Future<void> _newPlan(StudentRow row) async {
    final l10n = AppLocalizations.of(context);
    final title = await _askPlanTitle(l10n.studentsNewPlanDefaultTitle);
    if (title == null || !mounted) return;

    try {
      final plan = await ref.read(planRepositoryProvider).create(
            studentId: row.student.id,
            title: title,
          );
      if (!mounted) return;
      await _openPlan(plan.id);
    } catch (error) {
      if (!mounted) return;
      _showError(describeApiError(context, error));
    }
  }

  Future<String?> _askPlanTitle(String initial) {
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
        content: LyTextField(
          label: l10n.studentsPlanTitleLabel,
          controller: controller,
          autofocus: true,
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

  Future<void> _inviteStudent() async {
    final l10n = AppLocalizations.of(context);
    final name = TextEditingController();
    final email = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.studentsInviteTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LyTextField(label: l10n.studentsInviteNameLabel, controller: name),
            const SizedBox(height: LySpace.x3),
            LyTextField(
              label: l10n.studentsInviteEmailLabel,
              controller: email,
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.studentsInviteSubmit),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;

    try {
      await ref.read(studentRepositoryProvider).invite(
            email: email.text.trim(),
            name: name.text.trim(),
          );
      if (!mounted) return;
      ref.read(studentsProvider.notifier).refresh();
    } catch (error) {
      if (!mounted) return;
      _showError(describeApiError(context, error));
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final students = ref.watch(studentsProvider);

    return Scaffold(
      backgroundColor: c.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _inviteStudent,
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        icon: const Icon(Icons.person_add_alt),
        label: Text(l10n.studentsInviteSubmit),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(LySpace.x4),
            child: LyTextField(
              label: l10n.studentsSearchLabel,
              hint: l10n.studentsSearchHint,
              controller: _search,
              prefixIcon: Icons.search,
              onChanged: (value) =>
                  ref.read(studentQueryProvider.notifier).state = value,
            ),
          ),
          Expanded(
            child: students.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(LySpace.x6),
                  child: Text(
                    describeApiError(context, error),
                    textAlign: TextAlign.center,
                    style: LyType.body(c.textSecondary),
                  ),
                ),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return Center(
                    child: Text(
                      l10n.studentsEmpty,
                      style: LyType.body(c.textSecondary),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    LySpace.x4,
                    0,
                    LySpace.x4,
                    LySpace.x16,
                  ),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: LySpace.x2),
                  itemBuilder: (context, index) => _StudentTile(
                    row: rows[index],
                    onOpenPlan: _openPlan,
                    onNewPlan: () => _newPlan(rows[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentTile extends StatelessWidget {
  const _StudentTile({
    required this.row,
    required this.onOpenPlan,
    required this.onNewPlan,
  });

  final StudentRow row;
  final ValueChanged<String> onOpenPlan;
  final VoidCallback onNewPlan;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final plan = row.activePlan;

    return LyCard(
      padding: const EdgeInsets.all(LySpace.x4),
      onTap: plan == null ? onNewPlan : () => onOpenPlan(plan.id),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        row.student.name,
                        style: LyType.label(c.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (row.student.isPending) ...[
                      const SizedBox(width: LySpace.x2),
                      Text(
                        l10n.studentsPendingBadge,
                        style: LyType.caption(c.warning),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: LySpace.x1),
                Text(
                  plan == null
                      ? l10n.studentsNoPlan
                      : plan.publishedVersionNo == 0
                          ? l10n.studentsPlanDraft(plan.title)
                          : l10n.studentsPlanActive(
                              plan.title,
                              plan.publishedVersionNo,
                            ),
                  style: LyType.caption(c.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: LySpace.x3),
          LyButton(
            label: plan == null ? l10n.studentsNewPlan : l10n.studentsOpenPlan,
            variant: LyButtonVariant.secondary,
            expanded: false,
            onPressed: plan == null ? onNewPlan : () => onOpenPlan(plan.id),
          ),
        ],
      ),
    );
  }
}
