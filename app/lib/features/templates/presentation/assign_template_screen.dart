import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../students/domain/student.dart';
import '../../students/presentation/students_controller.dart';
import '../data/template_repository.dart';
import '../domain/template.dart';
import 'batch_result_view.dart';

/// Teto de alunos por lote no servidor (`assign`).
const int assignBatchLimit = 50;

/// "Aplicar a alunos" (P6.3 §2): seleção múltipla com busca, publicar já ou
/// como rascunho e o resultado por aluno (um aluno fora do vínculo não derruba
/// o lote — vem como erro naquele item).
class AssignTemplateScreen extends ConsumerStatefulWidget {
  const AssignTemplateScreen({
    required this.templateId,
    this.templateTitle,
    super.key,
  });

  final String templateId;
  final String? templateTitle;

  @override
  ConsumerState<AssignTemplateScreen> createState() =>
      _AssignTemplateScreenState();
}

class _AssignTemplateScreenState extends ConsumerState<AssignTemplateScreen> {
  static const int _pageSize = 30;

  final _search = TextEditingController();
  Timer? _debounce;
  int _generation = 0;

  StudentStatusFilter _status = StudentStatusFilter.active;
  List<Student> _students = [];
  String? _nextCursor;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  /// Seleção em ordem de escolha; sobrevive a mudar busca e filtro.
  final Set<String> _selected = {};
  final Map<String, String> _names = {};
  bool _publish = false;
  bool _submitting = false;
  List<BatchItem>? _results;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(studentRepositoryProvider).list(
            query: _search.text,
            status: _status,
            limit: _pageSize,
          );
      if (!mounted || generation != _generation) return;
      for (final s in page.items) {
        _names[s.id] = s.name;
      }
      setState(() {
        _students = page.items;
        _nextCursor = page.nextCursor;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_nextCursor == null || _loadingMore) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await ref.read(studentRepositoryProvider).list(
            query: _search.text,
            status: _status,
            cursor: _nextCursor,
            limit: _pageSize,
          );
      if (!mounted || generation != _generation) return;
      for (final s in page.items) {
        _names[s.id] = s.name;
      }
      setState(() {
        _students = [..._students, ...page.items];
        _nextCursor = page.nextCursor;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loadingMore = false;
        _error = error;
      });
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _reload);
  }

  void _toggle(String id, bool selected) {
    setState(() {
      if (selected) {
        if (_selected.length < assignBatchLimit) _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final items = await ref.read(templateRepositoryProvider).assign(
            widget.templateId,
            studentIds: _selected.toList(),
            publish: _publish,
          );
      if (!mounted) return;
      setState(() => _results = items);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Volta à seleção só com quem falhou, para tentar de novo.
  void _backToSelection(List<BatchItem> results) {
    setState(() {
      _selected
        ..clear()
        ..addAll([
          for (final r in results)
            if (!r.ok && r.studentId.isNotEmpty) r.studentId,
        ]);
      _results = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final results = _results;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: Text(l10n.assignTitle)),
      body: SafeArea(
        child: results != null
            ? BatchResultView(
                items: results,
                nameOf: (item) => _names[item.studentId] ?? item.studentId,
                okLabel: (item) => l10n.batchItemOk,
                onBackToSelection: () => _backToSelection(results),
              )
            : _buildSelection(context),
      ),
    );
  }

  Widget _buildSelection(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    String statusLabel(StudentStatusFilter f) => switch (f) {
          StudentStatusFilter.active => l10n.studentsFilterActive,
          StudentStatusFilter.inactive => l10n.studentsFilterInactive,
          StudentStatusFilter.invited => l10n.studentsFilterInvited,
        };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(LySpace.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.templateTitle != null) ...[
                Text(
                  l10n.assignTemplateName(widget.templateTitle!),
                  style: LyType.label(c.textPrimary),
                ),
                const SizedBox(height: LySpace.x3),
              ],
              LyTextField(
                label: l10n.studentsSearchLabel,
                hint: l10n.studentsSearchHint,
                controller: _search,
                prefixIcon: Icons.search,
                onChanged: _onSearchChanged,
              ),
              const SizedBox(height: LySpace.x3),
              Wrap(
                spacing: LySpace.x2,
                children: [
                  for (final f in StudentStatusFilter.values)
                    ChoiceChip(
                      key: Key('assign_filter_${f.apiValue}'),
                      label: Text(statusLabel(f)),
                      selected: _status == f,
                      onSelected: (_) {
                        _status = f;
                        _reload();
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        if (_error != null)
          Container(
            width: double.infinity,
            color: c.danger.withValues(alpha: 0.12),
            padding: const EdgeInsets.all(LySpace.x3),
            child: Text(
              describeApiError(context, _error!),
              style: LyType.bodySm(c.danger),
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  children: [
                    if (_students.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(LySpace.x6),
                        child: Text(
                          l10n.studentsEmptyFiltered,
                          textAlign: TextAlign.center,
                          style: LyType.body(c.textSecondary),
                        ),
                      ),
                    for (final student in _students)
                      CheckboxListTile(
                        key: Key('assign_student_${student.id}'),
                        value: _selected.contains(student.id),
                        onChanged: (value) =>
                            _toggle(student.id, value ?? false),
                        title: Text(
                          student.name,
                          style: LyType.label(c.textPrimary),
                        ),
                        subtitle: Text(
                          student.email,
                          style: LyType.caption(c.textSecondary),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    if (_nextCursor != null)
                      Center(
                        child: _loadingMore
                            ? const Padding(
                                padding: EdgeInsets.all(LySpace.x3),
                                child: CircularProgressIndicator(),
                              )
                            : TextButton(
                                onPressed: _loadMore,
                                child: Text(l10n.commonLoadMore),
                              ),
                      ),
                  ],
                ),
        ),
        // Material próprio: o SwitchListTile pinta o fundo no Material mais
        // próximo, e um Container colorido por cima o esconderia.
        Material(
          color: c.surface,
          child: Container(
            padding: const EdgeInsets.all(LySpace.x4),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.border)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  key: const Key('assign_publish'),
                  contentPadding: EdgeInsets.zero,
                  value: _publish,
                  onChanged: (v) => setState(() => _publish = v),
                  title: Text(l10n.assignPublishNow),
                  subtitle: Text(
                    l10n.assignPublishNowHint,
                    style: LyType.caption(c.textSecondary),
                  ),
                ),
                Text(
                  _selected.length >= assignBatchLimit
                      ? l10n.assignLimitReached(assignBatchLimit)
                      : l10n.assignSelected(_selected.length),
                  key: const Key('assign_selected_count'),
                  style: LyType.caption(c.textSecondary),
                ),
                const SizedBox(height: LySpace.x2),
                LyButton(
                  label: l10n.assignSubmit,
                  loading: _submitting,
                  onPressed: _selected.isEmpty || _submitting ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
