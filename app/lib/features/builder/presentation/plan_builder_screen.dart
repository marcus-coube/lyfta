import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/ly_shell_scaffold.dart';
import '../../evolution/domain/evolution_scope.dart';
import '../../profile/presentation/profile_controller.dart';
import '../../../shared/l10n/profile_l10n.dart';
import '../../templates/data/template_repository.dart';
import '../../templates/presentation/template_form_dialog.dart';
import '../data/plan_repository.dart';
import '../../../shared/domain/plan.dart';
import '../../../shared/l10n/plan_l10n.dart';
import 'widgets/exercise_picker.dart';
import 'widgets/set_editor.dart';
import 'widgets/version_history_sheet.dart';

/// Editor do plano do aluno (P1.6) e, na mesma tela, do modelo de treino
/// (P6.3, `kind=template`: sem aluno, com título e descrição editáveis).
///
/// Plano ou modelo **arquivado** abre em modo leitura (P6.2): o servidor
/// responde 409 `plan_archived`/`template_archived` a rascunho e publicação, e
/// a volta é só por Ativar/Desarquivar (ou Duplicar, no plano).
///
/// Ergonomia (P6.4): dias, blocos e exercícios se reordenam arrastando; dia e
/// bloco se duplicam; a série se copia para as próximas; o histórico de
/// versões abre cada versão em leitura; o rascunho mostra o aviso de
/// "alterações não publicadas" e as lesões ativas do aluno ficam no topo.
///
/// O rascunho vive no estado **local** desta tela, não num provider: um
/// editor de cinco níveis (dia → bloco → exercício → série) muda a cada
/// tecla, e propagar isso por um store global só criaria reconstrução sem
/// ganho. O que sai daqui é sempre a árvore inteira — `PUT /draft` substitui
/// tudo (P1.4).
///
/// Layout responsivo, sem tela separada por plataforma: master-detail acima
/// de [lyShellRailBreakpoint] (web/desktop), uma coluna com seletor de dia
/// abaixo (mobile).
class PlanBuilderScreen extends ConsumerStatefulWidget {
  const PlanBuilderScreen({required this.planId, super.key});

  final String planId;

  @override
  ConsumerState<PlanBuilderScreen> createState() => _PlanBuilderScreenState();
}

class _PlanBuilderScreenState extends ConsumerState<PlanBuilderScreen> {
  Plan? _plan;
  List<WorkoutDay> _days = [];
  String _title = '';
  String _description = '';
  int _selectedDay = 0;
  bool _dirty = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  /// Versão do histórico aberta em leitura; nulo = o plano atual.
  int? _viewingVersion;

  bool get _isTemplate => _plan?.isTemplate ?? false;
  bool get _readOnly => (_plan?.isArchived ?? false) || _viewingVersion != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plan = await ref.read(planRepositoryProvider).byId(widget.planId);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _title = plan.title;
        _description = plan.description;
        _days = plan.days;
        _selectedDay = 0;
        _dirty = false;
        _loading = false;
        _viewingVersion = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = describeApiError(context, error);
        _loading = false;
      });
    }
  }

  /// Abre a versão [versionNo] do histórico em leitura. Edição pendente é
  /// salva antes (como no "salvar como modelo"), para não se perder.
  Future<void> _openHistory() async {
    if (_dirty && !_readOnly) await _save();
    if (!mounted || _error != null) return;
    final picked = await showVersionHistory(context, planId: widget.planId);
    if (picked == null || !mounted) return;
    if (picked.isDraft) {
      await _load();
      return;
    }
    try {
      final plan = await ref
          .read(planRepositoryProvider)
          .byId(widget.planId, version: '${picked.versionNo}');
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _days = plan.days;
        _selectedDay = 0;
        _dirty = false;
        _error = null;
        _viewingVersion = picked.versionNo;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = describeApiError(context, error));
    }
  }

  void _markDirty() => setState(() => _dirty = true);

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final plan = await ref.read(planRepositoryProvider).saveDraft(
            planId: widget.planId,
            title: _title,
            description: _isTemplate ? _description : null,
            days: _days,
          );
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _days = plan.days;
        _dirty = false;
        _selectedDay =
            _selectedDay.clamp(0, plan.days.isEmpty ? 0 : plan.days.length - 1);
      });
      _toast(AppLocalizations.of(context).builderDraftSaved);
    } catch (error) {
      if (!mounted) return;
      await _onWriteError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Publicar congela a versão (ADR-004 §1), então é ação com confirmação —
  /// e o diálogo mostra o número da versão que vai nascer.
  Future<void> _publish() async {
    final l10n = AppLocalizations.of(context);
    if (_dirty) await _save();
    if (!mounted || _error != null) return;

    final nextVersion = _plan?.version?.versionNo ?? 1;
    final isTemplate = _isTemplate;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.builderPublishTitle),
        content: Text(
          isTemplate
              ? l10n.builderPublishTemplateBody(nextVersion)
              : l10n.builderPublishBody(nextVersion),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.builderPublish),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final plan =
          await ref.read(planRepositoryProvider).publish(widget.planId);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _days = plan.days;
        _dirty = false;
      });
      _toast(l10n.builderPublished(plan.version?.versionNo ?? nextVersion));
    } catch (error) {
      if (!mounted) return;
      await _onWriteError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Erro de rascunho/publicação. Plano arquivado por outra tela (409): mostra
  /// a mensagem e recarrega, que vira modo leitura em vez de deixar o coach
  /// editando algo que o servidor não aceita mais.
  Future<void> _onWriteError(Object error) async {
    final message = describeApiError(context, error);
    final archived = error is ApiException &&
        (error.code == 'plan_archived' || error.code == 'template_archived');
    if (archived) await _load();
    if (!mounted) return;
    setState(() => _error = message);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Atualiza o plano carregado depois de ativar/desarquivar sem perder o aviso.
  Future<void> _afterLifecycle(String message) async {
    await _load();
    if (mounted) _toast(message);
  }

  Future<void> _activate() async {
    final plan = _plan!;
    try {
      await ref
          .read(planRepositoryProvider)
          .activate(studentId: plan.studentId, planId: plan.id);
      if (!mounted) return;
      await _afterLifecycle(AppLocalizations.of(context).planActivated);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = describeApiError(context, error));
    }
  }

  Future<void> _unarchiveTemplate() async {
    try {
      await ref.read(templateRepositoryProvider).unarchive(widget.planId);
      if (!mounted) return;
      await _afterLifecycle(
        AppLocalizations.of(context).templatesUnarchivedToast,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = describeApiError(context, error));
    }
  }

  /// Duplica para um rascunho novo e abre a cópia no lugar deste plano.
  Future<void> _duplicate() async {
    final l10n = AppLocalizations.of(context);
    try {
      final copy =
          await ref.read(planRepositoryProvider).duplicate(widget.planId);
      if (!mounted) return;
      _toast(l10n.planDuplicated);
      context.pushReplacement('/plans/${copy.id}');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = describeApiError(context, error));
    }
  }

  /// Copia a versão mais recente (a que o servidor tem) para um modelo novo em
  /// rascunho. Salva antes se há edição pendente, senão o modelo nasceria sem
  /// o que está na tela.
  Future<void> _saveAsTemplate() async {
    final l10n = AppLocalizations.of(context);
    if (_dirty && !_readOnly) await _save();
    if (!mounted || _error != null) return;

    final form = await showTemplateFormDialog(
      context,
      heading: l10n.builderSaveAsTemplateTitle,
      initialTitle: _title,
      confirmKey: const Key('save_as_template_confirm'),
    );
    if (form == null || !mounted) return;

    try {
      final template = await ref
          .read(planRepositoryProvider)
          .saveAsTemplate(widget.planId, title: form.title);
      if (!mounted) return;
      // O aviso sobrevive à tela (ScaffoldMessenger é do app): o router é
      // capturado agora, e `persist: false` evita que a ação o deixe fixo
      // cobrindo o botão principal das telas seguintes.
      final router = GoRouter.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          persist: false,
          content: Text(l10n.builderSavedAsTemplate),
          action: SnackBarAction(
            label: l10n.builderOpenTemplate,
            onPressed: () => router.push<void>('/plans/${template.id}'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = describeApiError(context, error));
    }
  }

  /// O rótulo segue o alfabeto (A, B, C… é como o professor pensa a rotação),
  /// pegando a primeira letra livre: depois de remover o A, o dia novo não pode
  /// nascer "C" por ser o terceiro da lista.
  String _nextLabel() {
    final used = _days.map((d) => d.label).toSet();
    for (var i = 0; i < 26; i++) {
      final label = String.fromCharCode('A'.codeUnitAt(0) + i);
      if (!used.contains(label)) return label;
    }
    return '${_days.length + 1}';
  }

  void _addDay() {
    final label = _nextLabel();
    setState(() {
      _days.add(WorkoutDay(label: label));
      _selectedDay = _days.length - 1;
      _dirty = true;
    });
  }

  void _removeDay(int index) {
    setState(() {
      _days.removeAt(index);
      if (_selectedDay >= _days.length) {
        _selectedDay = _days.isEmpty ? 0 : _days.length - 1;
      }
      _dirty = true;
    });
  }

  void _moveDay(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _days.length) return;
    setState(() {
      final day = _days.removeAt(index);
      _days.insert(target, day);
      _selectedDay = target;
      _dirty = true;
    });
  }

  void _duplicateDay(int index) {
    setState(() {
      _days.insert(index + 1, _days[index].copy(label: _nextLabel()));
      _selectedDay = index + 1;
      _dirty = true;
    });
  }

  /// Arrastar na lista de dias; quem estava aberto continua aberto.
  void _reorderDay(int oldIndex, int newIndex) {
    if (newIndex == oldIndex) return;
    setState(() {
      final open = _days[_selectedDay];
      _days.insert(newIndex, _days.removeAt(oldIndex));
      _selectedDay = _days.indexOf(open);
      _dirty = true;
    });
  }

  void _reorderBlock(WorkoutDay day, int oldIndex, int newIndex) {
    if (newIndex == oldIndex) return;
    setState(() {
      day.blocks.insert(newIndex, day.blocks.removeAt(oldIndex));
      _dirty = true;
    });
  }

  void _duplicateBlock(WorkoutDay day, int index) {
    setState(() {
      day.blocks.insert(index + 1, day.blocks[index].copy());
      _dirty = true;
    });
  }

  Future<void> _addExercise(Block block) async {
    final exercise = await showExercisePicker(context);
    if (exercise == null) return;
    setState(() {
      block.exercises.add(
        BlockExercise(
          exerciseId: exercise.id,
          exercise: exercise,
          // Descanso padrão do bloco na série nova.
          sets: [
            PrescribedSet(
              repsMin: 8,
              repsMax: 12,
              restSeconds: block.restSeconds,
            ),
          ],
        ),
      );
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Text(_title.isEmpty ? l10n.builderTitle : _title),
        actions: [
          if (_plan?.version != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: LySpace.x3),
              child: Center(
                child: Text(
                  _plan!.version!.isDraft
                      ? l10n.builderDraftVersion(_plan!.version!.versionNo)
                      : l10n.builderPublishedVersion(_plan!.version!.versionNo),
                  style: LyType.caption(c.textSecondary),
                ),
              ),
            ),
          if (_plan != null && (_plan!.versions.isNotEmpty))
            IconButton(
              key: const Key('builder_history'),
              tooltip: l10n.builderHistory,
              icon: const Icon(Icons.history),
              onPressed: _openHistory,
            ),
          if (_plan != null && !_isTemplate && _viewingVersion == null)
            PopupMenuButton<String>(
              key: const Key('builder_menu'),
              icon: const Icon(Icons.more_vert),
              onSelected: (_) => _saveAsTemplate(),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'save_as_template',
                  child: Text(l10n.builderSaveAsTemplate),
                ),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  if (_error != null)
                    Container(
                      width: double.infinity,
                      color: c.danger.withValues(alpha: 0.12),
                      padding: const EdgeInsets.all(LySpace.x3),
                      child: Text(_error!, style: LyType.bodySm(c.danger)),
                    ),
                  if (_viewingVersion != null)
                    _buildViewingVersionBanner()
                  else if (_readOnly)
                    _buildReadOnlyBanner()
                  else if (_dirty || (_plan?.version?.isDraft ?? false))
                    _buildUnpublishedBanner(),
                  if (!_isTemplate && (_plan?.studentId ?? '').isNotEmpty)
                    _InjuriesBanner(studentId: _plan!.studentId),
                  // Largura da tela, não LayoutBuilder: o builder do
                  // LayoutBuilder roda durante o layout, e soltar um item
                  // arrastado reativa (GlobalKey) widgets com OverlayPortal
                  // (tooltips) — mexer no Overlay da rota nessa hora quebra
                  // com "_RenderLayoutBuilder was mutated in performLayout".
                  Expanded(
                    child: MediaQuery.sizeOf(context).width >=
                            lyShellRailBreakpoint
                        ? _buildWide()
                        : _buildNarrow(),
                  ),
                  if (!_readOnly)
                    _BuilderActions(
                      dirty: _dirty,
                      saving: _saving,
                      onSave: _save,
                      onPublish: _publish,
                    ),
                ],
              ),
            ),
    );
  }

  /// Rascunho com edição que o aluno ainda não vê.
  Widget _buildUnpublishedBanner() {
    final c = context.ly;
    return Container(
      key: const Key('builder_unpublished_banner'),
      width: double.infinity,
      color: c.accent.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(
        horizontal: LySpace.x3,
        vertical: LySpace.x2,
      ),
      child: Text(
        AppLocalizations.of(context).builderUnpublishedChanges,
        style: LyType.bodySm(c.textPrimary),
      ),
    );
  }

  /// Versão do histórico aberta: leitura, com a volta para o plano atual.
  Widget _buildViewingVersionBanner() {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    return Container(
      key: const Key('builder_viewing_version_banner'),
      width: double.infinity,
      color: c.warning.withValues(alpha: 0.12),
      padding: const EdgeInsets.all(LySpace.x3),
      child: Wrap(
        spacing: LySpace.x2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            l10n.builderViewingVersion(_viewingVersion!),
            style: LyType.bodySm(c.textPrimary),
          ),
          TextButton(
            key: const Key('builder_back_to_current'),
            onPressed: _load,
            child: Text(l10n.builderBackToCurrent),
          ),
        ],
      ),
    );
  }

  /// Plano/modelo arquivado: aviso de somente leitura com o caminho de volta.
  /// Plano arquivado que nunca foi publicado não reativa (422): só se
  /// aproveita duplicando.
  Widget _buildReadOnlyBanner() {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final plan = _plan!;
    final canActivate = !plan.isTemplate && plan.publishedVersionNo > 0;

    return Container(
      key: const Key('builder_read_only_banner'),
      width: double.infinity,
      color: c.warning.withValues(alpha: 0.12),
      padding: const EdgeInsets.all(LySpace.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plan.isTemplate
                ? l10n.builderReadOnlyTemplate
                : canActivate
                    ? l10n.builderReadOnlyPlan
                    : l10n.builderReadOnlyPlanNeverPublished,
            style: LyType.bodySm(c.textPrimary),
          ),
          const SizedBox(height: LySpace.x2),
          Wrap(
            spacing: LySpace.x2,
            children: [
              if (plan.isTemplate)
                TextButton(
                  key: const Key('builder_unarchive'),
                  onPressed: _unarchiveTemplate,
                  child: Text(l10n.templatesMenuUnarchive),
                ),
              if (canActivate)
                TextButton(
                  key: const Key('builder_activate'),
                  onPressed: _activate,
                  child: Text(l10n.planActivate),
                ),
              if (!plan.isTemplate)
                TextButton(
                  key: const Key('builder_duplicate'),
                  onPressed: _duplicate,
                  child: Text(l10n.planDuplicate),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Web/desktop: lista de dias à esquerda, dia aberto à direita.
  Widget _buildWide() {
    final c = context.ly;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 240,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: c.border)),
            ),
            child: _DayList(
              days: _days,
              selected: _selectedDay,
              onSelect: (index) => setState(() => _selectedDay = index),
              onAdd: _addDay,
              onRemove: _removeDay,
              onMove: _moveDay,
              onDuplicate: _duplicateDay,
              onReorder: _reorderDay,
              readOnly: _readOnly,
            ),
          ),
        ),
        Expanded(child: _buildDayEditor()),
      ],
    );
  }

  /// Mobile: seletor de dia em linha, editor embaixo.
  Widget _buildNarrow() {
    return Column(
      children: [
        SizedBox(
          height: 64,
          child: _DayChips(
            days: _days,
            selected: _selectedDay,
            onSelect: (index) => setState(() => _selectedDay = index),
            onAdd: _addDay,
            readOnly: _readOnly,
          ),
        ),
        Expanded(child: _buildDayEditor(withDayMenu: true)),
      ],
    );
  }

  Widget _buildDayEditor({bool withDayMenu = false}) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    if (_days.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(LySpace.x4),
        children: [
          if (_isTemplate) _buildTemplateHeader(),
          const SizedBox(height: LySpace.x6),
          Text(
            l10n.builderNoDays,
            textAlign: TextAlign.center,
            style: LyType.body(c.textSecondary),
          ),
          if (!_readOnly) ...[
            const SizedBox(height: LySpace.x4),
            Center(
              child: LyButton(
                label: l10n.builderAddDay,
                variant: LyButtonVariant.secondary,
                expanded: false,
                onPressed: _addDay,
              ),
            ),
          ],
        ],
      );
    }

    final day = _days[_selectedDay];
    final editable = <Widget>[
      Row(
        children: [
          Expanded(
            child: TextFormField(
              key: ValueKey('day-title-${day.label}-$_selectedDay'),
              initialValue: day.title,
              onChanged: (value) {
                day.title = value;
                _markDirty();
              },
              style: LyType.title(c.textPrimary),
              decoration: InputDecoration(
                labelText: l10n.builderDayTitle,
                labelStyle: LyType.caption(c.textSecondary),
              ),
            ),
          ),
          // Layout estreito não tem a lista de dias: o menu do dia vem aqui.
          if (withDayMenu && !_readOnly)
            _DayMenu(
              key: const Key('day_menu'),
              onMoveUp: _selectedDay > 0
                  ? () => _moveDay(_selectedDay, -1)
                  : null,
              onMoveDown: _selectedDay < _days.length - 1
                  ? () => _moveDay(_selectedDay, 1)
                  : null,
              onDuplicate: () => _duplicateDay(_selectedDay),
              onRemove: () => _removeDay(_selectedDay),
            ),
        ],
      ),
      const SizedBox(height: LySpace.x4),
      // Blocos reordenáveis por alça (sem rolagem própria: quem rola é a
      // lista da tela).
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorderItem: (from, to) => _reorderBlock(day, from, to),
        children: [
          for (var i = 0; i < day.blocks.length; i++)
            Padding(
              key: ObjectKey(day.blocks[i]),
              padding: const EdgeInsets.only(bottom: LySpace.x4),
              child: _BlockCard(
                index: i,
                block: day.blocks[i],
                readOnly: _readOnly,
                onChanged: _markDirty,
                onAddExercise: () => _addExercise(day.blocks[i]),
                onDuplicate: () => _duplicateBlock(day, i),
                onRemove: () => setState(() {
                  day.blocks.removeAt(i);
                  _dirty = true;
                }),
              ),
            ),
        ],
      ),
      if (!_readOnly)
        LyButton(
          label: l10n.builderAddBlock,
          variant: LyButtonVariant.secondary,
          icon: const Icon(Icons.add),
          onPressed: () => setState(() {
            day.blocks.add(Block());
            _dirty = true;
          }),
        ),
    ];
    // Somente leitura (plano/modelo arquivado, versão do histórico): o
    // conteúdo fica visível e rolável; os controles de estrutura somem e os
    // campos ficam sem toque nem foco.
    return ListView(
      padding: const EdgeInsets.all(LySpace.x4),
      children: [
        if (_isTemplate) ...[
          _buildTemplateHeader(),
          const SizedBox(height: LySpace.x4),
        ],
        IgnorePointer(
          ignoring: _readOnly,
          child: ExcludeFocus(
            excluding: _readOnly,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: editable,
            ),
          ),
        ),
        const SizedBox(height: LySpace.x12),
      ],
    );
  }

  /// Título e descrição do modelo (o plano do aluno não tem descrição).
  Widget _buildTemplateHeader() {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    return IgnorePointer(
      ignoring: _readOnly,
      child: ExcludeFocus(
        excluding: _readOnly,
        child: Column(
          children: [
            TextFormField(
              key: const Key('template_title'),
              initialValue: _title,
              onChanged: (value) {
                _title = value;
                _markDirty();
              },
              style: LyType.title(c.textPrimary),
              decoration: InputDecoration(
                labelText: l10n.templatesTitleLabel,
                labelStyle: LyType.caption(c.textSecondary),
              ),
            ),
            TextFormField(
              key: const Key('template_description'),
              initialValue: _description,
              minLines: 1,
              maxLines: 4,
              onChanged: (value) {
                _description = value;
                _markDirty();
              },
              style: LyType.body(c.textPrimary),
              decoration: InputDecoration(
                labelText: l10n.templatesDescriptionLabel,
                labelStyle: LyType.caption(c.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lista de dias do layout largo: a posição enviada ao servidor é a ordem
/// desta lista, que se reordena arrastando a alça (ou pelo menu, que serve
/// também ao teclado e ao leitor de tela).
class _DayList extends StatelessWidget {
  const _DayList({
    required this.days,
    required this.selected,
    required this.onSelect,
    required this.onAdd,
    required this.onRemove,
    required this.onMove,
    required this.onDuplicate,
    required this.onReorder,
    this.readOnly = false,
  });

  final List<WorkoutDay> days;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final void Function(int index, int delta) onMove;
  final ValueChanged<int> onDuplicate;
  final void Function(int oldIndex, int newIndex) onReorder;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    Widget tile(int i) => ListTile(
          key: ObjectKey(days[i]),
          selected: i == selected,
          selectedTileColor: c.surfaceElevated,
          shape: const RoundedRectangleBorder(borderRadius: LyRadius.md),
          title: Text(days[i].label, style: LyType.label(c.textPrimary)),
          subtitle: days[i].title.isEmpty
              ? null
              : Text(days[i].title, style: LyType.caption(c.textSecondary)),
          onTap: () => onSelect(i),
          leading: readOnly
              ? null
              : ReorderableDragStartListener(
                  index: i,
                  child: Tooltip(
                    message: l10n.builderReorderHandle,
                    child: Icon(
                      Icons.drag_indicator,
                      size: 20,
                      color: c.textSecondary,
                    ),
                  ),
                ),
          trailing: readOnly
              ? null
              : _DayMenu(
                  onMoveUp: i > 0 ? () => onMove(i, -1) : null,
                  onMoveDown:
                      i < days.length - 1 ? () => onMove(i, 1) : null,
                  onDuplicate: () => onDuplicate(i),
                  onRemove: () => onRemove(i),
                ),
        );

    final addButton = Padding(
      padding: const EdgeInsets.only(top: LySpace.x2),
      child: LyButton(
        label: l10n.builderAddDay,
        variant: LyButtonVariant.secondary,
        icon: const Icon(Icons.add),
        onPressed: onAdd,
      ),
    );

    if (readOnly) {
      return ListView(
        padding: const EdgeInsets.all(LySpace.x3),
        children: [for (var i = 0; i < days.length; i++) tile(i)],
      );
    }
    return ReorderableListView(
      key: const Key('day_list'),
      padding: const EdgeInsets.all(LySpace.x3),
      buildDefaultDragHandles: false,
      onReorderItem: onReorder,
      footer: addButton,
      children: [for (var i = 0; i < days.length; i++) tile(i)],
    );
  }
}

/// Menu de um dia: mover, duplicar e remover. Mover recebe `null` na ponta
/// da lista (o item aparece desabilitado).
class _DayMenu extends StatelessWidget {
  const _DayMenu({
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDuplicate,
    required this.onRemove,
    super.key,
  });

  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onDuplicate;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, size: 18, color: c.textSecondary),
      onSelected: (action) => switch (action) {
        'up' => onMoveUp?.call(),
        'down' => onMoveDown?.call(),
        'duplicate' => onDuplicate(),
        _ => onRemove(),
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'up',
          enabled: onMoveUp != null,
          child: Text(l10n.builderMoveUp),
        ),
        PopupMenuItem(
          value: 'down',
          enabled: onMoveDown != null,
          child: Text(l10n.builderMoveDown),
        ),
        PopupMenuItem(
          value: 'duplicate',
          child: Text(l10n.builderDuplicateDay),
        ),
        PopupMenuItem(value: 'remove', child: Text(l10n.commonRemove)),
      ],
    );
  }
}

/// Seletor de dia do layout estreito.
class _DayChips extends StatelessWidget {
  const _DayChips({
    required this.days,
    required this.selected,
    required this.onSelect,
    required this.onAdd,
    this.readOnly = false,
  });

  final List<WorkoutDay> days;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;

    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: LySpace.x4),
      children: [
        for (var i = 0; i < days.length; i++)
          Padding(
            padding: const EdgeInsets.only(
              right: LySpace.x2,
              top: LySpace.x2,
              bottom: LySpace.x2,
            ),
            child: ChoiceChip(
              selected: i == selected,
              onSelected: (_) => onSelect(i),
              label: Text(days[i].label),
            ),
          ),
        if (!readOnly)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: LySpace.x2),
            child: ActionChip(
              avatar: Icon(Icons.add, size: 16, color: c.textSecondary),
              label: Text(AppLocalizations.of(context).builderAddDay),
              onPressed: onAdd,
            ),
          ),
      ],
    );
  }
}

/// Alça de arrastar: some em leitura. O índice é o da lista reordenável mais
/// próxima (blocos no dia, exercícios no bloco).
class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    return ReorderableDragStartListener(
      index: index,
      child: Padding(
        padding: const EdgeInsets.only(right: LySpace.x2),
        child: Tooltip(
          message: AppLocalizations.of(context).builderReorderHandle,
          child: Icon(Icons.drag_indicator, size: 20, color: c.textSecondary),
        ),
      ),
    );
  }
}

/// Um bloco do dia: tipo, descanso e os exercícios com suas séries.
class _BlockCard extends StatelessWidget {
  const _BlockCard({
    required this.index,
    required this.block,
    required this.readOnly,
    required this.onChanged,
    required this.onAddExercise,
    required this.onDuplicate,
    required this.onRemove,
  });

  final int index;
  final Block block;
  final bool readOnly;
  final VoidCallback onChanged;
  final VoidCallback onAddExercise;
  final VoidCallback onDuplicate;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return LyCard(
      padding: const EdgeInsets.all(LySpace.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!readOnly) _DragHandle(index: index),
              Flexible(
                child: readOnly
                    ? Text(
                        blockTypeLabel(l10n, block.blockType),
                        style: LyType.label(c.textPrimary),
                      )
                    : DropdownButton<BlockType>(
                        value: block.blockType,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final type in BlockType.values)
                            DropdownMenuItem(
                              value: type,
                              child: Text(
                                blockTypeLabel(l10n, type),
                                style: LyType.label(c.textPrimary),
                              ),
                            ),
                        ],
                        onChanged: (type) {
                          if (type == null) return;
                          block.blockType = type;
                          onChanged();
                        },
                      ),
              ),
              const SizedBox(width: LySpace.x2),
              SizedBox(
                width: 110,
                child: TextFormField(
                  initialValue: block.restSeconds.toString(),
                  keyboardType: TextInputType.number,
                  onChanged: (raw) {
                    block.restSeconds = int.tryParse(raw) ?? 0;
                    onChanged();
                  },
                  style: LyType.body(c.textPrimary),
                  decoration: InputDecoration(
                    labelText: l10n.builderBlockRest,
                    labelStyle: LyType.caption(c.textSecondary),
                    isDense: true,
                  ),
                ),
              ),
              if (!readOnly)
                PopupMenuButton<String>(
                  key: const Key('block_menu'),
                  icon: Icon(Icons.more_vert, size: 18, color: c.textSecondary),
                  onSelected: (action) =>
                      action == 'duplicate' ? onDuplicate() : onRemove(),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'duplicate',
                      child: Text(l10n.builderDuplicateBlock),
                    ),
                    PopupMenuItem(
                      value: 'remove',
                      child: Text(l10n.commonRemove),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: LySpace.x3),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) {
              if (to == from) return;
              block.exercises.insert(to, block.exercises.removeAt(from));
              onChanged();
            },
            children: [
              for (var i = 0; i < block.exercises.length; i++)
                Padding(
                  key: ObjectKey(block.exercises[i]),
                  padding: const EdgeInsets.only(bottom: LySpace.x4),
                  child: _BlockExerciseEditor(
                    index: i,
                    item: block.exercises[i],
                    readOnly: readOnly,
                    defaultRestSeconds: block.restSeconds,
                    onChanged: onChanged,
                    onRemove: () {
                      block.exercises.removeAt(i);
                      onChanged();
                    },
                  ),
                ),
            ],
          ),
          if (!readOnly)
            TextButton.icon(
              onPressed: onAddExercise,
              icon: Icon(Icons.add, size: 18, color: c.accent),
              label:
                  Text(l10n.builderAddExercise, style: LyType.label(c.accent)),
            ),
        ],
      ),
    );
  }
}

class _BlockExerciseEditor extends StatelessWidget {
  const _BlockExerciseEditor({
    required this.index,
    required this.item,
    required this.readOnly,
    required this.defaultRestSeconds,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final BlockExercise item;
  final bool readOnly;
  final int defaultRestSeconds;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (!readOnly) _DragHandle(index: index),
            Expanded(
              child: Text(
                item.exercise?.name ?? l10n.builderUnknownExercise,
                style: LyType.label(c.textPrimary),
              ),
            ),
            if (!readOnly)
              IconButton(
                tooltip: l10n.commonRemove,
                onPressed: onRemove,
                icon: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: c.textSecondary,
                ),
              ),
          ],
        ),
        SetEditor(
          sets: item.sets,
          onChanged: onChanged,
          readOnly: readOnly,
          defaultRestSeconds: defaultRestSeconds,
        ),
      ],
    );
  }
}

/// Lesões ativas do aluno no topo do builder (P5.3), recolhível. Sem lesão
/// ativa, ou sem permissão/rede, não ocupa espaço: o builder não depende dela.
class _InjuriesBanner extends ConsumerStatefulWidget {
  const _InjuriesBanner({required this.studentId});

  final String studentId;

  @override
  ConsumerState<_InjuriesBanner> createState() => _InjuriesBannerState();
}

class _InjuriesBannerState extends ConsumerState<_InjuriesBanner> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final active = ref
            .watch(injuriesProvider(EvolutionScope.student(widget.studentId)))
            .valueOrNull
            ?.where((i) => i.active)
            .toList() ??
        const [];
    if (active.isEmpty) return const SizedBox.shrink();

    return Container(
      key: const Key('builder_injuries_banner'),
      width: double.infinity,
      color: c.danger.withValues(alpha: 0.10),
      padding: const EdgeInsets.symmetric(
        horizontal: LySpace.x3,
        vertical: LySpace.x1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const Key('builder_injuries_toggle'),
            onTap: () => setState(() => _open = !_open),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  Icon(Icons.healing_outlined, size: 18, color: c.danger),
                  const SizedBox(width: LySpace.x2),
                  Expanded(
                    child: Text(
                      l10n.builderInjuriesActive(active.length),
                      style: LyType.label(c.textPrimary),
                    ),
                  ),
                  Tooltip(
                    message: l10n.builderInjuriesToggle,
                    child: Icon(
                      _open ? Icons.expand_less : Icons.expand_more,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(bottom: LySpace.x2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final injury in active)
                    Text(
                      [
                        bodyRegionLabel(l10n, injury.bodyRegion),
                        if (injury.description.isNotEmpty) injury.description,
                      ].join(' · '),
                      style: LyType.bodySm(c.textSecondary),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Barra de ações fixa: salvar rascunho e publicar.
class _BuilderActions extends StatelessWidget {
  const _BuilderActions({
    required this.dirty,
    required this.saving,
    required this.onSave,
    required this.onPublish,
  });

  final bool dirty;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.all(LySpace.x4),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: LyButton(
              label: dirty ? l10n.builderSaveDraft : l10n.builderSaved,
              variant: LyButtonVariant.secondary,
              loading: saving && dirty,
              onPressed: dirty && !saving ? onSave : null,
            ),
          ),
          const SizedBox(width: LySpace.x3),
          Expanded(
            child: LyButton(
              label: l10n.builderPublish,
              loading: saving && !dirty,
              onPressed: saving ? null : onPublish,
            ),
          ),
        ],
      ),
    );
  }
}
