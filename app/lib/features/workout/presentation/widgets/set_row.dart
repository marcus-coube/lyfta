import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/l10n/gen/app_localizations.dart';
import '../../../../shared/domain/plan.dart';
import '../../domain/set_input.dart';
import '../../domain/today.dart';
import '../../domain/workout_event.dart';
import '../prescription_format.dart';

/// Callback de registro: repetições, carga e — quando é correção — o
/// `client_id` do log que está sendo revisado (ADR-003 §5).
typedef OnLogSet = Future<void> Function(int? reps, double? load, String? revises);

/// Uma linha de série no player.
///
/// Vem **pré-preenchida** (prescrição para as reps, última carga para o
/// peso): o aluno confere e toca em registrar. Digitar é a exceção, não a
/// regra — quem está entre séries não quer preencher formulário.
class SetRow extends StatefulWidget {
  const SetRow({
    required this.setNo,
    required this.prescribed,
    required this.onLog,
    this.previous,
    this.logged,
    super.key,
  });

  final int setNo;
  final PrescribedSet prescribed;
  final PreviousLoadSet? previous;
  final LocalSetLog? logged;
  final OnLogSet onLog;

  @override
  State<SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<SetRow> {
  late final TextEditingController _reps = TextEditingController(text: _initialReps);
  late TextEditingController _load;
  bool _loadInitialized = false;
  bool _saving = false;

  /// Resultado da última tentativa de registrar: campo fora do limite fica
  /// marcado até o aluno mexer nele de novo.
  SetInput? _rejected;

  /// Reps sai da prescrição: é o que o professor mandou fazer. O topo da
  /// faixa é o alvo — quem não alcançar, corrige para baixo.
  String get _initialReps {
    final p = widget.prescribed;
    final reps = p.repsMax ?? p.repsMin ?? widget.previous?.repsDone;
    return reps?.toString() ?? '';
  }

  /// Carga sai da **última vez**, não da prescrição: progressão de carga é o
  /// que o aluno faz na prática, e o alvo em kg pode nem existir (RPE/RIR).
  /// Precisa do `locale` (ADR-011 §4), só disponível a partir do `context` —
  /// por isso o controller nasce em [didChangeDependencies], não em
  /// [initState].
  String _initialLoad(String locale) {
    final load = widget.previous?.loadKg ?? widget.prescribed.targetLoadKg;
    return load == null ? '' : formatLoad(load, locale);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadInitialized) {
      final locale = Localizations.localeOf(context).toString();
      _load = TextEditingController(text: _initialLoad(locale));
      _loadInitialized = true;
    }
  }

  @override
  void dispose() {
    _reps.dispose();
    _load.dispose();
    super.dispose();
  }

  /// Registro da série pendente: só sai se os campos estiverem dentro do
  /// que o servidor aceita (A9 — rejeitado some da fila sem aviso).
  Future<void> _logPending() async {
    final input = SetInput.parse(reps: _reps.text, load: _load.text);
    if (!input.isValid) {
      setState(() => _rejected = input);
      return;
    }
    if (_rejected != null) setState(() => _rejected = null);
    await _submit(reps: input.reps, load: input.load);
  }

  Future<void> _submit({
    required int? reps,
    required double? load,
    String? revises,
  }) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onLog(reps, load, revises);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final logged = widget.logged;

    // Abaixo de ~420px os dois campos numéricos ao lado do rótulo ficariam
    // com ~70px cada e o rótulo flutuante ("Carga (kg)") não caberia. Em tela
    // estreita a série vira duas linhas — mesmo widget, `LayoutBuilder`
    // (guideline flutter.md), sem tela separada por plataforma.
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 420;
        final action = _ActionButton(
          setNo: widget.setNo,
          logged: logged,
          saving: _saving,
          onLog: _logPending,
          onFix: () => _openFix(logged!),
        );
        final content = logged == null
            ? _Inputs(
                reps: _reps,
                load: _load,
                saving: _saving,
                repsInvalid: _rejected?.repsInvalid ?? false,
                loadInvalid: _rejected?.loadInvalid ?? false,
                onChanged: () {
                  if (_rejected != null) setState(() => _rejected = null);
                },
              )
            : _LoggedSummary(log: logged);

        return Padding(
          padding: const EdgeInsets.only(bottom: LySpace.x3),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: _Label(setNo: widget.setNo, prescribed: widget.prescribed)),
                        action,
                      ],
                    ),
                    const SizedBox(height: LySpace.x2),
                    content,
                  ],
                )
              : Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: _Label(setNo: widget.setNo, prescribed: widget.prescribed),
                    ),
                    const SizedBox(width: LySpace.x2),
                    Expanded(child: content),
                    const SizedBox(width: LySpace.x2),
                    action,
                  ],
                ),
        );
      },
    );
  }

  /// Correção de uma série já registrada. Não edita o fato: manda outro log
  /// revisando o primeiro (ADR-003 §5).
  Future<void> _openFix(LocalSetLog logged) async {
    final locale = Localizations.localeOf(context).toString();
    final result = await showDialog<(int?, double?)>(
      context: context,
      builder: (dialogContext) => _FixSetDialog(
        setNo: widget.setNo,
        logged: logged,
        locale: locale,
      ),
    );
    if (result == null) return;
    await _submit(revises: logged.clientId, reps: result.$1, load: result.$2);
  }
}

/// Rótulo da série com a prescrição embaixo.
class _Label extends StatelessWidget {
  const _Label({required this.setNo, required this.prescribed});

  final int setNo;
  final PrescribedSet prescribed;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.sessionSet(setNo), style: LyType.label(c.textPrimary)),
        Text(
          prescriptionLabel(l10n, prescribed),
          style: LyType.caption(c.textSecondary),
        ),
      ],
    );
  }
}

/// Registrar (série pendente) ou corrigir (série já registrada).
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.setNo,
    required this.logged,
    required this.saving,
    required this.onLog,
    required this.onFix,
  });

  final int setNo;
  final LocalSetLog? logged;
  final bool saving;
  final VoidCallback onLog;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    if (logged == null) {
      return IconButton(
        onPressed: saving ? null : onLog,
        tooltip: l10n.sessionMarkDone,
        icon: const Icon(Icons.check_circle_outline),
        color: c.accent,
      );
    }
    return IconButton(
      onPressed: onFix,
      tooltip: l10n.sessionEditSet(setNo),
      icon: const Icon(Icons.edit_outlined),
      color: c.textSecondary,
    );
  }
}

class _Inputs extends StatelessWidget {
  const _Inputs({
    required this.reps,
    required this.load,
    required this.saving,
    required this.repsInvalid,
    required this.loadInvalid,
    required this.onChanged,
  });

  final TextEditingController reps;
  final TextEditingController load;
  final bool saving;
  final bool repsInvalid;
  final bool loadInvalid;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _NumberField(
            controller: reps,
            label: l10n.sessionReps,
            enabled: !saving,
            errorText: repsInvalid ? l10n.sessionRepsOutOfRange : null,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: LySpace.x2),
        Expanded(
          child: _NumberField(
            controller: load,
            label: l10n.sessionLoadKg,
            enabled: !saving,
            decimal: true,
            errorText: loadInvalid ? l10n.sessionLoadOutOfRange : null,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    this.enabled = true,
    this.decimal = false,
    this.errorText,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final bool decimal;
  final String? errorText;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;

    return TextField(
      controller: controller,
      enabled: enabled,
      onChanged: onChanged == null ? null : (_) => onChanged!(),
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          decimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]'),
        ),
      ],
      textAlign: TextAlign.center,
      style: LyType.numeric(c.textPrimary, size: 16),
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        errorMaxLines: 2,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: LySpace.x2,
          vertical: LySpace.x2,
        ),
      ),
    );
  }
}

class _LoggedSummary extends StatelessWidget {
  const _LoggedSummary({required this.log});

  final LocalSetLog log;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.sessionLoggedSet(
            log.repsDone?.toString() ?? l10n.sessionEmptyValue,
            log.loadKg == null
                ? l10n.sessionEmptyValue
                : formatLoad(log.loadKg!, l10n.localeName),
          ),
          style: LyType.body(c.textPrimary),
        ),
        Text(l10n.sessionSetDone, style: LyType.caption(c.success)),
      ],
    );
  }
}

class _FixSetDialog extends StatefulWidget {
  const _FixSetDialog({
    required this.setNo,
    required this.logged,
    required this.locale,
  });

  final int setNo;
  final LocalSetLog logged;
  final String locale;

  @override
  State<_FixSetDialog> createState() => _FixSetDialogState();
}

class _FixSetDialogState extends State<_FixSetDialog> {
  late final TextEditingController _reps =
      TextEditingController(text: widget.logged.repsDone?.toString() ?? '');
  late final TextEditingController _load = TextEditingController(
    text: widget.logged.loadKg == null
        ? ''
        : formatLoad(widget.logged.loadKg!, widget.locale),
  );

  SetInput? _rejected;

  @override
  void dispose() {
    _reps.dispose();
    _load.dispose();
    super.dispose();
  }

  /// Correção fora do limite não fecha o diálogo: é exatamente o caso do
  /// A9, em que o servidor descartaria a correção e as seguintes.
  void _save() {
    final input = SetInput.parse(reps: _reps.text, load: _load.text);
    if (!input.isValid) {
      setState(() => _rejected = input);
      return;
    }
    Navigator.of(context).pop((input.reps, input.load));
  }

  void _clearError() {
    if (_rejected != null) setState(() => _rejected = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.sessionEditSet(widget.setNo)),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _NumberField(
              controller: _reps,
              label: l10n.sessionReps,
              errorText: (_rejected?.repsInvalid ?? false)
                  ? l10n.sessionRepsOutOfRange
                  : null,
              onChanged: _clearError,
            ),
          ),
          const SizedBox(width: LySpace.x3),
          Expanded(
            child: _NumberField(
              controller: _load,
              label: l10n.sessionLoadKg,
              decimal: true,
              errorText: (_rejected?.loadInvalid ?? false)
                  ? l10n.sessionLoadOutOfRange
                  : null,
              onChanged: _clearError,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: _save,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
