import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/ly_date_field.dart';
import '../domain/student.dart';
import 'student_status.dart';
import 'students_controller.dart';

/// Aba Dados da ficha (P5.4): cadastro editável, status (inativar/reativar,
/// convite pendente), professor (owner) e histórico de status. A P5.5 acrescenta
/// "Objetivo e saúde" abaixo do cadastro.
class StudentDataTab extends ConsumerWidget {
  const StudentDataTab({required this.student, super.key});

  final Student student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = ref.watch(authControllerProvider.select((s) => s.isOwner));

    final registry = _RegistrySection(student: student);
    final status = _StatusSection(student: student);
    final coach = isOwner ? _CoachSection(student: student) : null;
    final history = _HistorySection(studentId: student.id);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Duas colunas em tela larga: cadastro de um lado, situação do outro.
        if (constraints.maxWidth >= 840) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(LySpace.x6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: registry),
                const SizedBox(width: LySpace.x8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      status,
                      if (coach != null) ...[
                        const SizedBox(height: LySpace.x6),
                        coach,
                      ],
                      const SizedBox(height: LySpace.x6),
                      history,
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(LySpace.x4),
          children: [
            registry,
            const SizedBox(height: LySpace.x6),
            status,
            if (coach != null) ...[const SizedBox(height: LySpace.x6), coach],
            const SizedBox(height: LySpace.x6),
            history,
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LySpace.x3),
      child: Text(label, style: LyType.title(context.ly.textPrimary)),
    );
  }
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Atualiza ficha e lista depois de uma mudança no aluno.
void _invalidateStudent(WidgetRef ref, String id) {
  ref.invalidate(studentDetailProvider(id));
  ref.invalidate(studentStatusHistoryProvider(id));
  ref.read(studentsProvider.notifier).refresh();
}

/// Nome, e-mail (somente leitura), telefone e nascimento.
class _RegistrySection extends ConsumerStatefulWidget {
  const _RegistrySection({required this.student});

  final Student student;

  @override
  ConsumerState<_RegistrySection> createState() => _RegistrySectionState();
}

class _RegistrySectionState extends ConsumerState<_RegistrySection> {
  late final _name = TextEditingController(text: widget.student.name);
  late final _phone = TextEditingController(text: widget.student.phone ?? '');
  late DateTime? _birth = widget.student.birthDate;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _name.text.trim() != widget.student.name ||
      _phone.text.trim() != (widget.student.phone ?? '') ||
      _birth != widget.student.birthDate;

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(studentRepositoryProvider).update(
            widget.student.id,
            name: _name.text.trim(),
            phone: _phone.text.trim(),
            // `''` apaga a data (contrato do PATCH).
            birthDate:
                _birth == null ? '' : DateFormat('yyyy-MM-dd').format(_birth!),
          );
      if (!mounted) return;
      _invalidateStudent(ref, widget.student.id);
      _snack(context, l10n.studentDataSaved);
    } catch (error) {
      if (mounted) _snack(context, describeApiError(context, error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l10n.studentDataSectionRegistry),
        LyTextField(
          key: const Key('student_name'),
          label: l10n.studentDataNameLabel,
          controller: _name,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: LySpace.x3),
        Text(l10n.studentDataEmailLabel, style: LyType.label(c.textPrimary)),
        const SizedBox(height: LySpace.x1),
        Text(
          widget.student.email,
          style: LyType.body(c.textSecondary),
        ),
        const SizedBox(height: LySpace.x3),
        LyTextField(
          key: const Key('student_phone'),
          label: l10n.profilePhoneLabel,
          controller: _phone,
          keyboardType: TextInputType.phone,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: LySpace.x3),
        LyDateField(
          label: l10n.profileBirthLabel,
          value: _birth,
          emptyLabel: l10n.profileBirthEmpty,
          clearLabel: l10n.profileBirthClear,
          firstDate: DateTime(1900),
          lastDate: DateTime(now.year, now.month, now.day),
          onChanged: (value) => setState(() => _birth = value),
        ),
        const SizedBox(height: LySpace.x4),
        LyButton(
          key: const Key('student_save'),
          label: l10n.commonSave,
          expanded: false,
          loading: _saving,
          onPressed:
              _dirty && _name.text.trim().isNotEmpty && !_saving ? _save : null,
        ),
      ],
    );
  }
}

/// Status atual, convite pendente (reenviar) e inativar/reativar.
class _StatusSection extends ConsumerStatefulWidget {
  const _StatusSection({required this.student});

  final Student student;

  @override
  ConsumerState<_StatusSection> createState() => _StatusSectionState();
}

class _StatusSectionState extends ConsumerState<_StatusSection> {
  bool _busy = false;

  /// Confirmação com motivo opcional. Devolve `null` se cancelou, senão o
  /// motivo (possivelmente vazio).
  Future<String?> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
  }) {
    final l10n = AppLocalizations.of(context);
    final reason = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body),
            const SizedBox(height: LySpace.x3),
            LyTextField(
              key: const Key('student_status_reason'),
              label: l10n.studentReasonLabel,
              controller: reason,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: const Key('student_status_confirm'),
            onPressed: () => Navigator.of(context).pop(reason.text.trim()),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      _invalidateStudent(ref, widget.student.id);
      _snack(context, done);
    } catch (error) {
      if (mounted) _snack(context, describeApiError(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deactivate() async {
    final l10n = AppLocalizations.of(context);
    final reason = await _confirm(
      title: l10n.studentDeactivateTitle(widget.student.name),
      body: l10n.studentDeactivateBody,
      confirmLabel: l10n.studentDeactivateConfirm,
    );
    if (reason == null || !mounted) return;
    await _run(
      () => ref
          .read(studentRepositoryProvider)
          .deactivate(widget.student.id, reason: reason),
      l10n.studentDeactivated,
    );
  }

  Future<void> _reactivate() async {
    final l10n = AppLocalizations.of(context);
    final reason = await _confirm(
      title: l10n.studentReactivateTitle(widget.student.name),
      body: l10n.studentReactivateBody,
      confirmLabel: l10n.studentReactivateConfirm,
    );
    if (reason == null || !mounted) return;
    await _run(
      () => ref
          .read(studentRepositoryProvider)
          .reactivate(widget.student.id, reason: reason),
      l10n.studentReactivated,
    );
  }

  Future<void> _resend(String invitationId) async {
    final l10n = AppLocalizations.of(context);
    await _run(
      () => ref.read(studentRepositoryProvider).resendInvitation(invitationId),
      l10n.studentInviteResent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final student = widget.student;
    final invitation = student.pendingInvitation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l10n.studentStatusSection),
        Text(
          studentStatusLabel(l10n, student.status),
          key: const Key('student_status_label'),
          style: LyType.label(
            student.isInactive ? c.textSecondary : c.textPrimary,
          ),
        ),
        if (student.isPending && invitation != null) ...[
          const SizedBox(height: LySpace.x2),
          Text(
            invitation.expired
                ? l10n.studentInviteExpired
                : l10n.studentInvitePending,
            style: LyType.bodySm(c.textSecondary),
          ),
          const SizedBox(height: LySpace.x3),
          LyButton(
            key: const Key('student_invite_resend'),
            label: l10n.studentInviteResend,
            variant: LyButtonVariant.secondary,
            expanded: false,
            onPressed: _busy ? null : () => _resend(invitation.id),
          ),
        ],
        if (student.status == 'active') ...[
          const SizedBox(height: LySpace.x3),
          LyButton(
            key: const Key('student_deactivate'),
            label: l10n.studentDeactivate,
            variant: LyButtonVariant.secondary,
            expanded: false,
            onPressed: _busy ? null : _deactivate,
          ),
        ],
        if (student.isInactive) ...[
          const SizedBox(height: LySpace.x3),
          LyButton(
            key: const Key('student_reactivate'),
            label: l10n.studentReactivate,
            expanded: false,
            onPressed: _busy ? null : _reactivate,
          ),
        ],
      ],
    );
  }
}

/// Professor responsável e "Trocar professor" (só owner, ADR-016): lista os
/// coaches e owners ativos e reatribui o aluno. Valer em até 30 s nos outros
/// serviços é a consistência eventual aceita no ADR.
class _CoachSection extends ConsumerWidget {
  const _CoachSection({required this.student});

  final Student student;

  Future<void> _change(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final repository = ref.read(studentRepositoryProvider);

    final List<CoachOption> coaches;
    try {
      coaches = await repository.listCoaches();
    } catch (error) {
      if (context.mounted) _snack(context, describeApiError(context, error));
      return;
    }
    if (!context.mounted) return;

    final chosen = await showModalBottomSheet<CoachOption>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(LySpace.x4),
                child: Text(
                  l10n.studentsChangeCoachTitle(student.name),
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
                  trailing: coach.id == student.coachId
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(coach),
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null || chosen.id == student.coachId || !context.mounted) {
      return;
    }

    try {
      await repository.reassignCoach(
        studentId: student.id,
        coachId: chosen.id,
      );
      if (!context.mounted) return;
      _invalidateStudent(ref, student.id);
      _snack(context, l10n.studentsCoachChanged(chosen.name));
    } catch (error) {
      if (context.mounted) _snack(context, describeApiError(context, error));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l10n.studentCoachSection),
        Text(
          (student.coachName ?? '').isEmpty
              ? l10n.studentCoachNone
              : student.coachName!,
          style: LyType.body(c.textPrimary),
        ),
        const SizedBox(height: LySpace.x3),
        LyButton(
          key: const Key('student_change_coach'),
          label: l10n.studentsChangeCoach,
          variant: LyButtonVariant.secondary,
          expanded: false,
          onPressed: () => _change(context, ref),
        ),
      ],
    );
  }
}

/// Mudanças de status, da mais recente para a mais antiga (inclui o aceite
/// do convite).
class _HistorySection extends ConsumerWidget {
  const _HistorySection({required this.studentId});

  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final history = ref.watch(studentStatusHistoryProvider(studentId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l10n.studentHistorySection),
        history.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(LySpace.x2),
            child: CircularProgressIndicator(),
          ),
          error: (error, _) => Row(
            children: [
              Expanded(
                child: Text(
                  describeApiError(context, error),
                  style: LyType.bodySm(c.danger),
                ),
              ),
              if (isRetryableError(error))
                TextButton(
                  onPressed: () =>
                      ref.invalidate(studentStatusHistoryProvider(studentId)),
                  child: Text(l10n.commonRetry),
                ),
            ],
          ),
          data: (events) {
            if (events.isEmpty) {
              return Text(
                l10n.studentHistoryEmpty,
                style: LyType.body(c.textSecondary),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in events)
                  Padding(
                    padding: const EdgeInsets.only(bottom: LySpace.x3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.studentHistoryEntry(
                            studentStatusLabel(l10n, e.from),
                            studentStatusLabel(l10n, e.to),
                          ),
                          style: LyType.label(c.textPrimary),
                        ),
                        Text(
                          [
                            DateFormat.yMMMd(locale)
                                .add_Hm()
                                .format(e.createdAt),
                            if (e.changedByName.isNotEmpty)
                              l10n.studentHistoryBy(e.changedByName),
                          ].join(' · '),
                          style: LyType.caption(c.textSecondary),
                        ),
                        if ((e.reason ?? '').isNotEmpty)
                          Text(
                            e.reason!,
                            style: LyType.bodySm(c.textSecondary),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
