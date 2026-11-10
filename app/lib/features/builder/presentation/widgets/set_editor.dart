import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/l10n/gen/app_localizations.dart';
import '../../../../shared/domain/plan.dart';
import '../../../../shared/l10n/plan_l10n.dart';

/// Editor da prescrição estruturada de um exercício (ADR-012 §4).
///
/// Uma linha por série: faixa de repetições, alvo (kg | %1RM | RPE | RIR) e
/// descanso. **Não** existe campo de texto livre aqui de propósito: o gráfico
/// de carga do MVP depende de a prescrição ser consultável, e "3x10 pesado"
/// não é.
///
/// As séries são objetos mutáveis editados no lugar; [onChanged] só avisa a
/// tela que algo mudou (para habilitar o salvar), não carrega o novo valor.
///
/// Em [readOnly] (plano arquivado, versão do histórico) as ações de estrutura
/// — adicionar, duplicar, copiar para as próximas, remover, unidade — somem.
class SetEditor extends StatelessWidget {
  const SetEditor({
    required this.sets,
    required this.onChanged,
    this.readOnly = false,
    this.defaultRestSeconds,
    super.key,
  });

  final List<PrescribedSet> sets;
  final VoidCallback onChanged;
  final bool readOnly;

  /// Descanso padrão do bloco: a série que nasce sem anterior para copiar usa
  /// este valor. Série adicionada depois copia a anterior (descanso incluso).
  final int? defaultRestSeconds;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < sets.length; i++)
          Padding(
            key: ObjectKey(sets[i]),
            padding: const EdgeInsets.only(bottom: LySpace.x2),
            child: _SetRow(
              set: sets[i],
              index: i,
              readOnly: readOnly,
              onChanged: onChanged,
              onCopyToNext: i < sets.length - 1
                  ? () {
                      // Objetos novos (e não só campos copiados): cada linha
                      // guarda os controllers do que mostrou na 1ª montagem, e
                      // a chave por objeto os recria com o valor novo.
                      for (var j = i + 1; j < sets.length; j++) {
                        sets[j] = sets[i].copy();
                      }
                      onChanged();
                    }
                  : null,
              onDuplicate: () {
                // Duplicar é o gesto mais usado do editor: séries de um
                // exercício quase sempre repetem a anterior com um ajuste.
                sets.insert(i + 1, sets[i].copy());
                onChanged();
              },
              onRemove: sets.length > 1
                  ? () {
                      sets.removeAt(i);
                      onChanged();
                    }
                  : null,
            ),
          ),
        if (!readOnly)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('set-editor-add'),
              onPressed: () {
                // A série nova nasce como cópia da última: continuar a
                // prescrição é mais comum do que começar do zero. Sem
                // anterior, vale o descanso padrão do bloco.
                sets.add(
                  sets.isEmpty
                      ? PrescribedSet(restSeconds: defaultRestSeconds)
                      : sets.last.copy(),
                );
                onChanged();
              },
              icon: Icon(Icons.add, size: 18, color: c.accent),
              label: Text(l10n.builderAddSet, style: LyType.label(c.accent)),
            ),
          ),
      ],
    );
  }
}

/// Uma linha de série. Os campos escrevem direto no objeto: o rascunho
/// inteiro é reenviado no salvar (`PUT /draft` substitui a árvore), então não
/// há estado intermediário a reconciliar.
class _SetRow extends StatefulWidget {
  const _SetRow({
    required this.set,
    required this.index,
    required this.readOnly,
    required this.onChanged,
    required this.onDuplicate,
    required this.onCopyToNext,
    required this.onRemove,
  });

  final PrescribedSet set;
  final int index;
  final bool readOnly;
  final VoidCallback onChanged;
  final VoidCallback onDuplicate;
  final VoidCallback? onCopyToNext;
  final VoidCallback? onRemove;

  @override
  State<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<_SetRow> {
  late final TextEditingController _repsMin;
  late final TextEditingController _repsMax;
  late final TextEditingController _target;
  late final TextEditingController _rest;

  @override
  void initState() {
    super.initState();
    _repsMin = TextEditingController(text: _asText(widget.set.repsMin));
    _repsMax = TextEditingController(text: _asText(widget.set.repsMax));
    _target = TextEditingController(text: _asText(_targetValueOf(widget.set)));
    _rest = TextEditingController(text: _asText(widget.set.restSeconds));
  }

  @override
  void dispose() {
    _repsMin.dispose();
    _repsMax.dispose();
    _target.dispose();
    _rest.dispose();
    super.dispose();
  }

  static String _asText(num? value) {
    if (value == null) return '';
    if (value is double && value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  /// O alvo mora em dois campos: `target_load_kg` para carga absoluta,
  /// `target_value` para os relativos (%1RM/RPE/RIR).
  static num? _targetValueOf(PrescribedSet set) {
    final unit = set.targetUnit;
    if (unit == null || unit == TargetUnit.kg) return set.targetLoadKg;
    return set.targetValue;
  }

  void _writeTarget(String raw) {
    final value = double.tryParse(raw.replaceAll(',', '.'));
    final unit = widget.set.targetUnit ?? TargetUnit.kg;
    if (unit == TargetUnit.kg) {
      widget.set
        ..targetLoadKg = value
        ..targetValue = null;
    } else {
      widget.set
        ..targetValue = value
        ..targetLoadKg = null;
    }
    widget.onChanged();
  }

  void _changeUnit(TargetUnit unit) {
    setState(() {
      widget.set.targetUnit = unit;
      // Trocar de unidade move o número para o campo certo — 40 kg não vira
      // RPE 40.
      _writeTarget(_target.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final unit = widget.set.targetUnit ?? TargetUnit.kg;

    final number = SizedBox(
      width: _indexWidth,
      child: Text(
        '${widget.index + 1}',
        style: LyType.numeric(c.textSecondary, size: 14),
      ),
    );
    final repsMin = Expanded(
      child: _NumberField(
        key: Key('set-${widget.index}-reps-min'),
        label: l10n.builderRepsMin,
        controller: _repsMin,
        onChanged: (raw) {
          widget.set.repsMin = int.tryParse(raw);
          widget.onChanged();
        },
      ),
    );
    final repsMax = Expanded(
      child: _NumberField(
        key: Key('set-${widget.index}-reps-max'),
        label: l10n.builderRepsMax,
        controller: _repsMax,
        onChanged: (raw) {
          widget.set.repsMax = int.tryParse(raw);
          widget.onChanged();
        },
      ),
    );
    final target = Expanded(
      child: _NumberField(
        key: Key('set-${widget.index}-target'),
        label: targetUnitLabel(l10n, unit),
        controller: _target,
        allowDecimal: true,
        onChanged: _writeTarget,
      ),
    );
    final unitMenu = SizedBox(
      width: LySpace.x10,
      child: PopupMenuButton<TargetUnit>(
        key: Key('set-${widget.index}-unit'),
        tooltip: l10n.builderTargetUnit,
        icon: Icon(Icons.swap_vert, size: 18, color: c.textSecondary),
        enabled: !widget.readOnly,
        onSelected: _changeUnit,
        itemBuilder: (context) => [
          for (final option in TargetUnit.values)
            PopupMenuItem(
              value: option,
              child: Text(targetUnitLabel(l10n, option)),
            ),
        ],
      ),
    );
    final rest = Expanded(
      child: _NumberField(
        key: Key('set-${widget.index}-rest'),
        label: l10n.builderRestSeconds,
        controller: _rest,
        onChanged: (raw) {
          widget.set.restSeconds = int.tryParse(raw);
          widget.onChanged();
        },
      ),
    );
    final duplicate = IconButton(
      key: Key('set-${widget.index}-duplicate'),
      tooltip: l10n.builderDuplicateSet,
      onPressed: widget.onDuplicate,
      icon: Icon(Icons.copy_outlined, size: 18, color: c.textSecondary),
    );
    // Remover e copiar para as próximas dividem um menu: ficam longe do
    // gesto mais usado (duplicar) e não custam largura a mais na linha.
    final more = PopupMenuButton<String>(
      key: Key('set-${widget.index}-menu'),
      icon: Icon(Icons.more_vert, size: 18, color: c.textSecondary),
      onSelected: (action) =>
          action == 'copy' ? widget.onCopyToNext!() : widget.onRemove!(),
      itemBuilder: (context) => [
        if (widget.onCopyToNext != null)
          PopupMenuItem(
            key: Key('set-${widget.index}-copy-next'),
            value: 'copy',
            child: Text(l10n.builderCopyToNext),
          ),
        PopupMenuItem(
          key: Key('set-${widget.index}-remove'),
          value: 'remove',
          enabled: widget.onRemove != null,
          child: Text(l10n.commonRemove),
        ),
      ],
    );
    final actions = widget.readOnly ? const <Widget>[] : [duplicate, more];
    const gap = SizedBox(width: LySpace.x2);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _singleRowMinWidth) {
          return Row(
            children: [
              number, repsMin, gap, repsMax, gap, target, unitMenu, gap, rest,
              ...actions,
            ],
          );
        }

        // Estreito (celular): faixa de reps + ações em cima, alvo e
        // descanso embaixo — cada campo fica com metade da linha em vez de
        // um quarto. Duplicar continua à vista: é o gesto mais usado.
        return Column(
          children: [
            Row(children: [number, repsMin, gap, repsMax, ...actions]),
            const SizedBox(height: LySpace.x2),
            Row(
              children: [
                const SizedBox(width: _indexWidth),
                target, unitMenu, gap, rest,
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Largura da coluna do número da série.
const double _indexWidth = 28;

/// Abaixo disto a linha de série quebra em duas fileiras. Numa fileira só,
/// número + unidade + 3 vãos + 2 botões comem ~188 px; com 520 cada um dos 4
/// campos ainda fica com ~80 px — o bastante para "52.5" e para o rótulo.
const double _singleRowMinWidth = 520;

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.allowDecimal = false,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool allowDecimal;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;

    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          allowDecimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]'),
        ),
      ],
      style: LyType.body(c.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: LyType.caption(c.textSecondary),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: LySpace.x3,
          vertical: LySpace.x3,
        ),
      ),
    );
  }
}
