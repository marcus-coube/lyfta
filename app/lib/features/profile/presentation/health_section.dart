import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/l10n/profile_l10n.dart';
import '../../evolution/domain/evolution_scope.dart';
import '../data/profile_repository.dart';
import '../domain/student_profile.dart';
import 'injury_form_dialog.dart';
import 'profile_controller.dart';

/// "Objetivo e saúde" (P5.5): a anamnese do aluno. Na ficha do coach
/// ([EvolutionScope.student]) traz também as notas privadas e as lesões; na
/// tela "Meu objetivo" do aluno ([EvolutionScope.me]) são só objetivo,
/// experiência, meta semanal e observações médicas.
class HealthSection extends ConsumerWidget {
  const HealthSection({required this.scope, super.key});

  final EvolutionScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(studentProfileProvider(scope));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: LySpace.x3),
          child: Text(
            l10n.profileHealthSection,
            style: LyType.title(c.textPrimary),
          ),
        ),
        profile.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(LySpace.x4),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => _SectionError(
            key: const Key('health_error'),
            error: error,
            coachScope: scope.isCoach,
            onRetry: () => ref.invalidate(studentProfileProvider(scope)),
          ),
          data: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProfileForm(scope: scope, profile: data),
              // O aluno também vê e edita as próprias lesões (decisão do
              // produto, P5.5): informa antes de treinar, o coach vê na ficha.
              const SizedBox(height: LySpace.x6),
              _InjuriesList(scope: scope),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({
    required this.error,
    required this.coachScope,
    required this.onRetry,
    super.key,
  });

  final Object error;
  final bool coachScope;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.error_outline, color: c.danger),
      title: Text(describeScopedError(context, error, coachScope: coachScope)),
      trailing: isRetryableError(error)
          ? TextButton(onPressed: onRetry, child: Text(l10n.commonRetry))
          : null,
    );
  }
}

/// Formulário da anamnese. O `PUT` substitui tudo o que a porta escreve, então
/// o formulário parte do perfil lido e sempre devolve os campos completos.
class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({required this.scope, required this.profile});

  final EvolutionScope scope;
  final StudentProfile profile;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  late final _goalNotes = TextEditingController();
  late final _medicalNotes = TextEditingController();
  late final _coachNotes = TextEditingController();
  late String? _goal;
  late String? _experience;
  late int? _weeklyTarget;
  late StudentProfile _saved;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load(widget.profile);
  }

  void _load(StudentProfile p) {
    _saved = p;
    _goal = p.goal;
    _experience = p.trainingExperience;
    _weeklyTarget = p.weeklyTarget;
    _goalNotes.text = p.goalNotes;
    _medicalNotes.text = p.medicalNotes;
    _coachNotes.text = p.coachNotes;
  }

  @override
  void dispose() {
    _goalNotes.dispose();
    _medicalNotes.dispose();
    _coachNotes.dispose();
    super.dispose();
  }

  StudentProfile get _draft => StudentProfile(
        goal: _goal,
        goalNotes: _goalNotes.text.trim(),
        trainingExperience: _experience,
        weeklyTarget: _weeklyTarget,
        medicalNotes: _medicalNotes.text.trim(),
        coachNotes: widget.scope.isCoach ? _coachNotes.text.trim() : '',
      );

  bool get _dirty {
    final d = _draft;
    return d.goal != _saved.goal ||
        d.goalNotes != _saved.goalNotes ||
        d.trainingExperience != _saved.trainingExperience ||
        d.weeklyTarget != _saved.weeklyTarget ||
        d.medicalNotes != _saved.medicalNotes ||
        (widget.scope.isCoach && d.coachNotes != _saved.coachNotes);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(profileRepositoryProvider)
          .saveProfile(widget.scope, _draft);
      if (!mounted) return;
      setState(() => _load(saved));
      messenger.showSnackBar(SnackBar(content: Text(l10n.profileHealthSaved)));
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              describeScopedError(
                context,
                error,
                coachScope: widget.scope.isCoach,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Picker<String>(
          fieldKey: const Key('profile_goal'),
          label: l10n.profileGoalLabel,
          unsetLabel: l10n.profileUnset,
          value: _goal,
          options: goalCodes,
          optionLabel: (code) => goalLabel(l10n, code),
          onChanged: (v) => setState(() => _goal = v),
        ),
        const SizedBox(height: LySpace.x3),
        LyTextField(
          key: const Key('profile_goal_notes'),
          label: l10n.profileGoalNotesLabel,
          controller: _goalNotes,
          minLines: 2,
          maxLines: 4,
          maxLength: goalNotesMaxLength,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: LySpace.x3),
        _Picker<String>(
          fieldKey: const Key('profile_experience'),
          label: l10n.profileExperienceLabel,
          unsetLabel: l10n.profileUnset,
          value: _experience,
          options: experienceCodes,
          optionLabel: (code) => experienceLabel(l10n, code),
          onChanged: (v) => setState(() => _experience = v),
        ),
        const SizedBox(height: LySpace.x3),
        // A meta semanal alimenta o streak da Agenda e é do coach: o aluno
        // só lê (o backend ignora o campo na porta `/me`).
        if (widget.scope.isCoach)
          _Picker<int>(
            fieldKey: const Key('profile_weekly_target'),
            label: l10n.profileWeeklyTargetLabel,
            unsetLabel: l10n.profileUnset,
            value: _weeklyTarget,
            options: const [1, 2, 3, 4, 5, 6, 7],
            optionLabel: l10n.profileWeeklyTargetOption,
            onChanged: (v) => setState(() => _weeklyTarget = v),
          )
        else
          _ReadOnlyField(
            fieldKey: const Key('profile_weekly_target_readonly'),
            label: l10n.profileWeeklyTargetLabel,
            value: _weeklyTarget == null
                ? l10n.profileUnset
                : l10n.profileWeeklyTargetOption(_weeklyTarget!),
            hint: l10n.profileWeeklyTargetCoachOnly,
          ),
        const SizedBox(height: LySpace.x3),
        LyTextField(
          key: const Key('profile_medical_notes'),
          label: l10n.profileMedicalNotesLabel,
          hint: l10n.profileMedicalNotesHint,
          controller: _medicalNotes,
          minLines: 3,
          maxLines: 6,
          maxLength: medicalNotesMaxLength,
          onChanged: (_) => setState(() {}),
        ),
        if (widget.scope.isCoach) ...[
          const SizedBox(height: LySpace.x3),
          LyTextField(
            key: const Key('profile_coach_notes'),
            label: l10n.profileCoachNotesLabel,
            hint: l10n.profileCoachNotesHint,
            controller: _coachNotes,
            minLines: 3,
            maxLines: 6,
            maxLength: coachNotesMaxLength,
            onChanged: (_) => setState(() {}),
          ),
        ],
        const SizedBox(height: LySpace.x4),
        LyButton(
          key: const Key('profile_health_save'),
          label: l10n.commonSave,
          expanded: false,
          loading: _saving,
          onPressed: _dirty && !_saving ? _save : null,
        ),
      ],
    );
  }
}

/// Seletor com a opção "não informado" (valor nulo).
class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.hint,
  });

  final Key fieldKey;
  final String label;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    return Column(
      key: fieldKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: LyType.label(c.textPrimary)),
        const SizedBox(height: LySpace.x2),
        Text(value, style: LyType.body(c.textPrimary)),
        const SizedBox(height: LySpace.x1),
        Text(hint, style: LyType.caption(c.textSecondary)),
      ],
    );
  }
}

class _Picker<T> extends StatelessWidget {
  const _Picker({
    required this.fieldKey,
    required this.label,
    required this.unsetLabel,
    required this.value,
    required this.options,
    required this.optionLabel,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final String unsetLabel;
  final T? value;
  final List<T> options;
  final String Function(T) optionLabel;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: LyType.label(c.textPrimary)),
        const SizedBox(height: LySpace.x2),
        DropdownButtonFormField<T?>(
          key: fieldKey,
          initialValue: value,
          isExpanded: true,
          items: [
            DropdownMenuItem<T?>(value: null, child: Text(unsetLabel)),
            for (final option in options)
              DropdownMenuItem<T?>(
                value: option,
                child: Text(optionLabel(option)),
              ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Lesões do aluno na ficha do coach: adicionar, resolver/reabrir e remover.
class _InjuriesList extends ConsumerStatefulWidget {
  const _InjuriesList({required this.scope});

  final EvolutionScope scope;

  @override
  ConsumerState<_InjuriesList> createState() => _InjuriesListState();
}

class _InjuriesListState extends ConsumerState<_InjuriesList> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    final coach = widget.scope.isCoach;
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(injuriesProvider(widget.scope));
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content:
                Text(describeScopedError(context, error, coachScope: coach)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final input = await showInjuryFormDialog(context);
    if (input == null || !mounted) return;
    await _run(
      () => ref.read(profileRepositoryProvider).addInjury(widget.scope, input),
    );
  }

  Future<void> _delete(Injury injury) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.injuryDeleteTitle),
        content: Text(l10n.injuryDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: const Key('injury_delete_confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.commonRemove),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(
      () => ref
          .read(profileRepositoryProvider)
          .deleteInjury(widget.scope, injury.id),
    );
  }

  Future<void> _toggleResolved(Injury injury) {
    final now = DateTime.now();
    return _run(
      () => ref.read(profileRepositoryProvider).setResolved(
            widget.scope,
            injury.id,
            injury.active ? DateTime(now.year, now.month, now.day) : null,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final injuries = ref.watch(injuriesProvider(widget.scope));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.injuriesSection, style: LyType.label(c.textPrimary)),
        const SizedBox(height: LySpace.x2),
        injuries.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(LySpace.x4),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => _SectionError(
            error: error,
            coachScope: widget.scope.isCoach,
            onRetry: () => ref.invalidate(injuriesProvider(widget.scope)),
          ),
          data: (items) {
            final active = items.where((i) => i.active).toList();
            final resolved = items.where((i) => !i.active).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: LySpace.x2),
                    child: Text(
                      l10n.injuriesEmpty,
                      style: LyType.body(c.textSecondary),
                    ),
                  ),
                for (final injury in active)
                  _InjuryTile(
                    injury: injury,
                    busy: _busy,
                    onToggle: () => _toggleResolved(injury),
                    onDelete: () => _delete(injury),
                  ),
                if (resolved.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(
                      top: LySpace.x3,
                      bottom: LySpace.x1,
                    ),
                    child: Text(
                      l10n.injuriesResolvedHeader,
                      style: LyType.caption(c.textSecondary),
                    ),
                  ),
                  for (final injury in resolved)
                    _InjuryTile(
                      injury: injury,
                      busy: _busy,
                      onToggle: () => _toggleResolved(injury),
                      onDelete: () => _delete(injury),
                    ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: LySpace.x2),
        LyButton(
          key: const Key('injury_add'),
          label: l10n.injuriesAdd,
          variant: LyButtonVariant.secondary,
          expanded: false,
          onPressed: _busy ? null : _add,
        ),
      ],
    );
  }
}

class _InjuryTile extends StatelessWidget {
  const _InjuryTile({
    required this.injury,
    required this.busy,
    required this.onToggle,
    required this.onDelete,
  });

  final Injury injury;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final date = DateFormat.yMMMd(Localizations.localeOf(context).toString());
    final dates = [
      if (injury.since != null) l10n.injurySinceOn(date.format(injury.since!)),
      if (injury.resolvedAt != null)
        l10n.injuryResolvedOn(date.format(injury.resolvedAt!)),
    ].join(' · ');
    final textColor = injury.active ? c.textPrimary : c.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: LySpace.x2),
      child: LyCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bodyRegionLabel(l10n, injury.bodyRegion),
                    style: LyType.label(textColor),
                  ),
                  const SizedBox(height: LySpace.x1),
                  Text(injury.description, style: LyType.body(textColor)),
                  if (dates.isNotEmpty) ...[
                    const SizedBox(height: LySpace.x1),
                    Text(dates, style: LyType.caption(c.textSecondary)),
                  ],
                ],
              ),
            ),
            PopupMenuButton<bool>(
              key: Key('injury_menu_${injury.id}'),
              enabled: !busy,
              onSelected: (remove) => remove ? onDelete() : onToggle(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: false,
                  child: Text(
                    injury.active ? l10n.injuryResolve : l10n.injuryReopen,
                  ),
                ),
                PopupMenuItem(value: true, child: Text(l10n.commonRemove)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
