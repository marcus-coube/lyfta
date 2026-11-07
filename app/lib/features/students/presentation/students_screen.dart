import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/ly_error_state.dart';
import '../../../shared/widgets/ly_skeleton.dart';
import '../../builder/data/plan_repository.dart';
import '../../chat/presentation/conversations_controller.dart';
import '../domain/student.dart';
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

  /// Abre a ficha de evolução do aluno (P2.5). O nome vai por `extra` só
  /// para o título — a tela funciona sem ele quando a URL é aberta direto.
  void _openEvolution(StudentRow row) {
    context.push<void>(
      '/students/${row.student.id}/evolution',
      extra: row.student.name,
    );
  }

  /// Abre (ou recupera) a conversa com o aluno e navega para ela — mesmo
  /// get-or-create do `POST /v1/conversations` (P3.2), então tocar de novo
  /// no mesmo aluno nunca cria uma segunda conversa. Passa pelo
  /// `ConversationsController` (não o repositório direto) para a lista de
  /// conversas já nascer atualizada da próxima vez que a aba Chat abrir.
  Future<void> _openChat(StudentRow row) async {
    try {
      final conversation =
          await ref.read(conversationsProvider.notifier).start(row.student.id);
      if (!mounted) return;
      await context.push<void>(
        '/chat/${conversation.id}',
        extra: row.student.name,
      );
    } catch (error) {
      if (!mounted) return;
      _showError(describeApiError(context, error));
    }
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
        // Column mínimo como no convite: o LyTextField sozinho esticava o
        // diálogo até a altura da tela (E2E P4.4).
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

  /// "Trocar professor" (só owner, ADR-016): lista os coaches e owners ativos
  /// e reatribui o aluno. Valer em até 30 s nos outros serviços é a
  /// consistência eventual aceita no ADR.
  Future<void> _changeCoach(StudentRow row) async {
    final l10n = AppLocalizations.of(context);
    final repository = ref.read(studentRepositoryProvider);

    final List<CoachOption> coaches;
    try {
      coaches = await repository.listCoaches();
    } catch (error) {
      if (!mounted) return;
      _showError(describeApiError(context, error));
      return;
    }
    if (!mounted) return;

    final chosen = await showModalBottomSheet<CoachOption>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(LySpace.x4),
              child: Text(
                l10n.studentsChangeCoachTitle(row.student.name),
                style: LyType.label(sheetContext.ly.textPrimary),
              ),
            ),
            if (coaches.isEmpty)
              Padding(
                padding: const EdgeInsets.all(LySpace.x4),
                child: Text(
                  l10n.studentsCoachesEmpty,
                  style: LyType.body(sheetContext.ly.textSecondary),
                ),
              ),
            for (final coach in coaches)
              ListTile(
                title: Text(coach.name),
                trailing: coach.id == row.student.coachId
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(coach),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || chosen.id == row.student.coachId || !mounted) return;

    try {
      await repository.reassignCoach(
        studentId: row.student.id,
        coachId: chosen.id,
      );
      if (!mounted) return;
      ref.read(studentsProvider.notifier).refresh();
      _showError(l10n.studentsCoachChanged(chosen.name));
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
    final isOwner = ref.watch(authControllerProvider.select((s) => s.isOwner));

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
              loading: () => ListView.separated(
                padding: const EdgeInsets.all(LySpace.x4),
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 6,
                separatorBuilder: (_, __) => const SizedBox(height: LySpace.x3),
                itemBuilder: (context, index) => const LySkeletonListTile(),
              ),
              error: (error, _) => LyErrorState(
                message: describeApiError(context, error),
                retryable: isRetryableError(error),
                onRetry: () => ref.read(studentsProvider.notifier).refresh(),
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
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: LySpace.x2),
                  itemBuilder: (context, index) => _StudentTile(
                    row: rows[index],
                    onOpenPlan: _openPlan,
                    onNewPlan: () => _newPlan(rows[index]),
                    onOpenEvolution: () => _openEvolution(rows[index]),
                    onOpenChat: () => _openChat(rows[index]),
                    // Só o owner vê o professor e troca (ADR-016 §2).
                    onChangeCoach:
                        isOwner ? () => _changeCoach(rows[index]) : null,
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
    required this.onOpenEvolution,
    required this.onOpenChat,
    this.onChangeCoach,
  });

  final StudentRow row;
  final ValueChanged<String> onOpenPlan;
  final VoidCallback onNewPlan;
  final VoidCallback onOpenEvolution;
  final VoidCallback onOpenChat;

  /// Nulo para o coach comum: a ação "Trocar professor" e o nome do professor
  /// são só do owner.
  final VoidCallback? onChangeCoach;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final plan = row.activePlan;
    final coachName = row.student.coachName;

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
                if (onChangeCoach != null && (coachName ?? '').isNotEmpty) ...[
                  const SizedBox(height: LySpace.x1),
                  Text(
                    l10n.studentsCoachLabel(coachName!),
                    style: LyType.caption(c.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: LySpace.x2),
          // Evolução fica ao lado do plano, não no lugar dele: são as duas
          // coisas que o professor faz com um aluno (montar treino e
          // acompanhar progresso), e o toque no card segue abrindo o plano
          // como no P1.6.
          IconButton(
            onPressed: onOpenEvolution,
            icon: const Icon(Icons.show_chart),
            color: c.textSecondary,
            tooltip: l10n.studentsOpenEvolution,
          ),
          // Chat fica ao lado da Evolução pelo mesmo motivo (P3.5 §1): abrir
          // conversa é algo que o professor faz com o aluno sem substituir
          // as outras ações do card.
          IconButton(
            onPressed: onOpenChat,
            icon: const Icon(Icons.chat_bubble_outline),
            color: c.textSecondary,
            tooltip: l10n.studentsOpenChat,
          ),
          if (onChangeCoach != null)
            IconButton(
              onPressed: onChangeCoach,
              icon: const Icon(Icons.swap_horiz),
              color: c.textSecondary,
              tooltip: l10n.studentsChangeCoach,
            ),
          const SizedBox(width: LySpace.x2),
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
