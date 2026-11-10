import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/ly_error_state.dart';
import '../../../shared/widgets/ly_skeleton.dart';
import '../../chat/presentation/conversations_controller.dart';
import '../domain/student.dart';
import 'student_status.dart';
import 'students_controller.dart';

/// Abaixo desta largura a lista é de cartões; a partir dela vira tabela
/// (mesmo corte do shell, P5.4 §1).
const double studentsTableBreakpoint = 840;

/// Professores para o filtro do owner (ativos, sem repetir quem é owner e
/// coach). Falhar aqui só esconde o filtro — a lista continua funcionando.
final _coachOptionsProvider =
    FutureProvider.autoDispose<List<CoachOption>>((ref) {
  return ref.watch(studentRepositoryProvider).listCoaches();
});

/// Lista de alunos do professor: busca, filtros de status e professor,
/// paginação incremental e, em tela larga, tabela. Tocar numa linha abre a
/// ficha (`/students/:id`).
class StudentsScreen extends ConsumerStatefulWidget {
  const StudentsScreen({super.key});

  @override
  ConsumerState<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends ConsumerState<StudentsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Espera o professor parar de digitar: cada tecla refazia a consulta (e a
  /// chamada de resumo em lote).
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(studentQueryProvider.notifier).state = value;
    });
  }

  void _openStudent(Student student) {
    context.push<void>('/students/${student.id}', extra: student.name);
  }

  /// Abre (ou recupera) a conversa com o aluno e navega para ela — mesmo
  /// get-or-create do `POST /v1/conversations` (P3.2), então tocar de novo
  /// no mesmo aluno nunca cria uma segunda conversa. Passa pelo
  /// `ConversationsController` (não o repositório direto) para a lista de
  /// conversas já nascer atualizada da próxima vez que a aba Chat abrir.
  Future<void> _openChat(Student student) async {
    try {
      final conversation =
          await ref.read(conversationsProvider.notifier).start(student.id);
      if (!mounted) return;
      await context.push<void>('/chat/${conversation.id}', extra: student.name);
    } catch (error) {
      if (!mounted) return;
      _showError(describeApiError(context, error));
    }
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
    final isOwner = ref.watch(authControllerProvider.select((s) => s.isOwner));
    final filtered = ref.watch(studentQueryProvider).trim().isNotEmpty ||
        ref.watch(studentStatusFilterProvider) != StudentStatusFilter.active ||
        ref.watch(studentCoachFilterProvider) != null;

    return Scaffold(
      backgroundColor: c.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _inviteStudent,
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        icon: const Icon(Icons.person_add_alt),
        label: Text(l10n.studentsInviteSubmit),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= studentsTableBreakpoint;
          // O cabeçalho (busca + filtros) é o primeiro item da própria lista:
          // rola junto e não disputa altura com ela — numa janela baixa a
          // coluna fixa estourava (dívida do P1.8).
          final header = _Header(
            search: _search,
            onSearchChanged: _onSearchChanged,
            isOwner: isOwner,
          );

          return students.when(
            loading: () => ListView(
              padding: const EdgeInsets.all(LySpace.x4),
              physics: const NeverScrollableScrollPhysics(),
              children: [
                header,
                for (var i = 0; i < 6; i++) ...[
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
                    onRetry: () =>
                        ref.read(studentsProvider.notifier).refresh(),
                  ),
                ),
              ],
            ),
            data: (state) {
              if (state.rows.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.all(LySpace.x4),
                  children: [
                    header,
                    const SizedBox(height: LySpace.x8),
                    Center(
                      child: Text(
                        filtered
                            ? l10n.studentsEmptyFiltered
                            : l10n.studentsEmpty,
                        style: LyType.body(c.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                );
              }
              // Cabeçalho + (títulos da tabela) + linhas + (rodapé).
              final lead = wide ? 2 : 1;
              final footer = state.hasMore ? 1 : 0;
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(
                  LySpace.x4,
                  LySpace.x4,
                  LySpace.x4,
                  LySpace.x16,
                ),
                itemCount: lead + state.rows.length + footer,
                itemBuilder: (context, index) {
                  if (index == 0) return header;
                  if (wide && index == 1) {
                    return _TableHeader(showCoach: isOwner);
                  }
                  final rowIndex = index - lead;
                  if (rowIndex >= state.rows.length) {
                    return _LoadMoreFooter(state: state);
                  }
                  final row = state.rows[rowIndex];
                  return Padding(
                    padding: const EdgeInsets.only(top: LySpace.x2),
                    child: wide
                        ? _StudentTableRow(
                            row: row,
                            showCoach: isOwner,
                            onOpen: () => _openStudent(row.student),
                            onOpenChat: () => _openChat(row.student),
                          )
                        : _StudentTile(
                            row: row,
                            showCoach: isOwner,
                            onOpen: () => _openStudent(row.student),
                            onOpenChat: () => _openChat(row.student),
                          ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// Busca, filtro de status e (owner) filtro de professor.
class _Header extends ConsumerWidget {
  const _Header({
    required this.search,
    required this.onSearchChanged,
    required this.isOwner,
  });

  final TextEditingController search;
  final ValueChanged<String> onSearchChanged;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(studentStatusFilterProvider);
    final coachId = ref.watch(studentCoachFilterProvider);
    final coaches = isOwner
        ? ref.watch(_coachOptionsProvider).valueOrNull ?? const <CoachOption>[]
        : const <CoachOption>[];

    String label(StudentStatusFilter f) => switch (f) {
          StudentStatusFilter.active => l10n.studentsFilterActive,
          StudentStatusFilter.inactive => l10n.studentsFilterInactive,
          StudentStatusFilter.invited => l10n.studentsFilterInvited,
        };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LyTextField(
          label: l10n.studentsSearchLabel,
          hint: l10n.studentsSearchHint,
          controller: search,
          prefixIcon: Icons.search,
          onChanged: onSearchChanged,
        ),
        const SizedBox(height: LySpace.x3),
        Wrap(
          spacing: LySpace.x2,
          runSpacing: LySpace.x2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final f in StudentStatusFilter.values)
              ChoiceChip(
                key: Key('students_filter_${f.apiValue}'),
                label: Text(label(f)),
                selected: status == f,
                onSelected: (_) =>
                    ref.read(studentStatusFilterProvider.notifier).state = f,
              ),
            if (coaches.isNotEmpty)
              DropdownButton<String?>(
                key: const Key('students_filter_coach'),
                value: coachId,
                hint: Text(l10n.studentsFilterCoachLabel),
                underline: const SizedBox.shrink(),
                style: LyType.body(c.textPrimary),
                onChanged: (value) =>
                    ref.read(studentCoachFilterProvider.notifier).state = value,
                items: [
                  DropdownMenuItem<String?>(
                    child: Text(l10n.studentsFilterCoachAll),
                  ),
                  for (final coach in coaches)
                    DropdownMenuItem<String?>(
                      value: coach.id,
                      child: Text(coach.name),
                    ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

String _planText(AppLocalizations l10n, StudentRow row) {
  final plan = row.activePlan;
  if (plan == null) return l10n.studentsNoPlan;
  return l10n.studentsPlanActive(plan.title, plan.versionNo);
}

/// "Hoje", "Ontem", "Há N dias" ou "Nunca treinou", por dia civil local.
String _lastWorkoutText(AppLocalizations l10n, DateTime? last) {
  if (last == null) return l10n.studentsLastWorkoutNever;
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(last.year, last.month, last.day))
      .inDays;
  if (days <= 0) return l10n.studentsLastWorkoutToday;
  if (days == 1) return l10n.studentsLastWorkoutYesterday;
  return l10n.studentsLastWorkoutDaysAgo(days);
}

Color _statusColor(LyColors c, String status) => switch (status) {
      'invited' => c.warning,
      'active' => c.success,
      _ => c.textSecondary,
    };

/// Cartão do celular: nome, status quando não é "ativo", plano e professor.
class _StudentTile extends StatelessWidget {
  const _StudentTile({
    required this.row,
    required this.showCoach,
    required this.onOpen,
    required this.onOpenChat,
  });

  final StudentRow row;
  final bool showCoach;
  final VoidCallback onOpen;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final student = row.student;
    final coachName = student.coachName;

    return LyCard(
      padding: const EdgeInsets.all(LySpace.x4),
      onTap: onOpen,
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
                        student.name,
                        style: LyType.label(c.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (student.status != 'active') ...[
                      const SizedBox(width: LySpace.x2),
                      Text(
                        studentStatusLabel(l10n, student.status),
                        style: LyType.caption(_statusColor(c, student.status)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: LySpace.x1),
                Text(
                  _planText(l10n, row),
                  style: LyType.caption(c.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
                if (student.status == 'active') ...[
                  const SizedBox(height: LySpace.x1),
                  Text(
                    '${l10n.studentsColLastWorkout}: '
                    '${_lastWorkoutText(l10n, row.lastSessionAt)}',
                    style: LyType.caption(c.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (showCoach && (coachName ?? '').isNotEmpty) ...[
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
          IconButton(
            onPressed: onOpenChat,
            icon: const Icon(Icons.chat_bubble_outline),
            color: c.textSecondary,
            tooltip: l10n.studentsOpenChat,
          ),
        ],
      ),
    );
  }
}

// Proporção das colunas da tabela (nome sempre; professor só para o owner).
const _colName = 3;
const _colCoach = 2;
const _colPlan = 3;
const _colLast = 2;
const _colStatus = 2;

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.showCoach});

  final bool showCoach;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final style = LyType.caption(c.textSecondary);

    return Padding(
      padding: const EdgeInsets.fromLTRB(LySpace.x4, LySpace.x4, LySpace.x4, 0),
      child: Row(
        children: [
          Expanded(
            flex: _colName,
            child: Text(l10n.studentsColName, style: style),
          ),
          if (showCoach)
            Expanded(
              flex: _colCoach,
              child: Text(l10n.studentsColCoach, style: style),
            ),
          Expanded(
            flex: _colPlan,
            child: Text(l10n.studentsColPlan, style: style),
          ),
          Expanded(
            flex: _colLast,
            child: Text(l10n.studentsColLastWorkout, style: style),
          ),
          Expanded(
            flex: _colStatus,
            child: Text(l10n.studentsColStatus, style: style),
          ),
          // Espaço do botão de chat.
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

/// Linha da tabela (tela larga): nome, professor (owner), plano, status.
class _StudentTableRow extends StatelessWidget {
  const _StudentTableRow({
    required this.row,
    required this.showCoach,
    required this.onOpen,
    required this.onOpenChat,
  });

  final StudentRow row;
  final bool showCoach;
  final VoidCallback onOpen;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final student = row.student;

    return LyCard(
      padding: const EdgeInsets.symmetric(
        horizontal: LySpace.x4,
        vertical: LySpace.x2,
      ),
      onTap: onOpen,
      child: Row(
        children: [
          Expanded(
            flex: _colName,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.name,
                  style: LyType.label(c.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  student.email,
                  style: LyType.caption(c.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (showCoach)
            Expanded(
              flex: _colCoach,
              child: Text(
                student.coachName ?? '',
                style: LyType.body(c.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Expanded(
            flex: _colPlan,
            child: Text(
              _planText(l10n, row),
              style: LyType.body(c.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colLast,
            child: Text(
              student.status == 'active'
                  ? _lastWorkoutText(l10n, row.lastSessionAt)
                  : '',
              style: LyType.body(c.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _colStatus,
            child: Text(
              studentStatusLabel(l10n, student.status),
              style: LyType.body(_statusColor(c, student.status)),
            ),
          ),
          IconButton(
            onPressed: onOpenChat,
            icon: const Icon(Icons.chat_bubble_outline),
            color: c.textSecondary,
            tooltip: l10n.studentsOpenChat,
          ),
        ],
      ),
    );
  }
}

/// Último item quando há mais páginas: ao ser construído (a lista chegou
/// perto do fim) pede a próxima. Se a página falhar, para e oferece "tentar
/// de novo" — sem isso, a API fora viraria um laço de requisições.
class _LoadMoreFooter extends ConsumerStatefulWidget {
  const _LoadMoreFooter({required this.state});

  final StudentsState state;

  @override
  ConsumerState<_LoadMoreFooter> createState() => _LoadMoreFooterState();
}

class _LoadMoreFooterState extends ConsumerState<_LoadMoreFooter> {
  void _maybeLoad() {
    final s = widget.state;
    if (s.loadingMore || s.loadMoreFailed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(studentsProvider.notifier).loadMore();
    });
  }

  @override
  void initState() {
    super.initState();
    _maybeLoad();
  }

  @override
  void didUpdateWidget(_LoadMoreFooter old) {
    super.didUpdateWidget(old);
    // Chegou a página e ainda há mais com o rodapé na tela (lista curta
    // demais para rolar): continua puxando até preencher.
    _maybeLoad();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    if (widget.state.loadMoreFailed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: LySpace.x4),
        child: Column(
          children: [
            Text(
              l10n.studentsLoadMoreError,
              style: LyType.bodySm(c.textSecondary),
            ),
            TextButton(
              onPressed: () => ref.read(studentsProvider.notifier).loadMore(),
              child: Text(l10n.commonRetry),
            ),
          ],
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: LySpace.x4),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}
