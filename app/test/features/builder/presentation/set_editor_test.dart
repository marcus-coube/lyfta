import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/shared/domain/plan.dart';
import 'package:lyfta/features/builder/presentation/widgets/set_editor.dart';

/// Monta o editor isolado, com tema e i18n reais — é o componente que o
/// professor mais usa no builder (P1.6).
Future<List<PrescribedSet>> _pumpEditor(
  WidgetTester tester, {
  List<PrescribedSet>? sets,
}) async {
  final list = sets ?? [PrescribedSet(repsMin: 8, repsMax: 12, restSeconds: 60)];
  var changes = 0;

  await tester.pumpWidget(
    MaterialApp(
      theme: LyTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: SetEditor(
              sets: list,
              onChanged: () => setState(() => changes++),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return list;
}

void main() {
  testWidgets('mostra uma linha por série prescrita', (tester) async {
    await _pumpEditor(
      tester,
      sets: [
        PrescribedSet(repsMin: 8, repsMax: 12, targetLoadKg: 40),
        PrescribedSet(repsMin: 6, repsMax: 8, targetLoadKg: 45),
      ],
    );

    expect(find.byKey(const Key('set-0-reps-min')), findsOneWidget);
    expect(find.byKey(const Key('set-1-reps-min')), findsOneWidget);
    expect(find.byKey(const Key('set-2-reps-min')), findsNothing);

    // A prescrição chega preenchida: o professor edita, não redigita.
    final target = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('set-0-target')),
        matching: find.byType(TextField),
      ),
    );
    expect(target.controller?.text, '40');
  });

  testWidgets('adicionar série copia a última — continuar a prescrição é o caso comum',
      (tester) async {
    final sets = await _pumpEditor(
      tester,
      sets: [PrescribedSet(repsMin: 10, repsMax: 12, targetLoadKg: 30, restSeconds: 90)],
    );

    await tester.tap(find.byKey(const Key('set-editor-add')));
    await tester.pumpAndSettle();

    expect(sets.length, 2);
    expect(sets[1].repsMin, 10);
    expect(sets[1].targetLoadKg, 30);
    expect(sets[1].restSeconds, 90);
    expect(find.byKey(const Key('set-1-reps-min')), findsOneWidget);
  });

  testWidgets('editar uma linha escreve na série correspondente', (tester) async {
    final sets = await _pumpEditor(
      tester,
      sets: [PrescribedSet(repsMin: 8, repsMax: 12, targetLoadKg: 40, restSeconds: 60)],
    );

    await tester.enterText(find.byKey(const Key('set-0-reps-min')), '6');
    await tester.enterText(find.byKey(const Key('set-0-reps-max')), '10');
    await tester.enterText(find.byKey(const Key('set-0-target')), '52.5');
    await tester.enterText(find.byKey(const Key('set-0-rest')), '120');
    await tester.pumpAndSettle();

    expect(sets.single.repsMin, 6);
    expect(sets.single.repsMax, 10);
    expect(sets.single.targetLoadKg, 52.5);
    expect(sets.single.restSeconds, 120);
  });

  testWidgets('copiar para as próximas sobrescreve as seguintes e a última não oferece',
      (tester) async {
    final sets = await _pumpEditor(
      tester,
      sets: [
        PrescribedSet(repsMin: 5, repsMax: 6, targetLoadKg: 60, restSeconds: 90),
        PrescribedSet(repsMin: 12, targetLoadKg: 20),
        PrescribedSet(repsMin: 15, targetLoadKg: 10),
      ],
    );

    // A última não tem próximas: o item nem existe no menu.
    await tester.tap(find.byKey(const Key('set-2-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('set-2-copy-next')), findsNothing);
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('set-0-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('set-0-copy-next')));
    await tester.pumpAndSettle();

    expect(sets.length, 3);
    for (final set in sets.skip(1)) {
      expect(set.repsMin, 5);
      expect(set.targetLoadKg, 60);
      expect(set.restSeconds, 90);
    }
    // A tela mostra o valor novo (os campos foram recriados, não só o modelo).
    final reps = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('set-2-reps-min')),
        matching: find.byType(TextField),
      ),
    );
    expect(reps.controller?.text, '5');
    expect(identical(sets[1], sets[2]), isFalse);
  });

  testWidgets('sem série anterior a nova usa o descanso padrão do bloco',
      (tester) async {
    final sets = <PrescribedSet>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: LyTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: SetEditor(
                sets: sets,
                defaultRestSeconds: 75,
                onChanged: () => setState(() {}),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('set-editor-add')));
    await tester.pumpAndSettle();

    expect(sets.single.restSeconds, 75);
  });

  testWidgets('em leitura não há adicionar, duplicar, copiar nem remover',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LyTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SetEditor(
              sets: [PrescribedSet(repsMin: 8), PrescribedSet(repsMin: 10)],
              readOnly: true,
              onChanged: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('set-editor-add')), findsNothing);
    expect(find.byKey(const Key('set-0-duplicate')), findsNothing);
    expect(find.byKey(const Key('set-0-menu')), findsNothing);
    expect(find.byKey(const Key('set-1-reps-min')), findsOneWidget);
  });

  testWidgets('duplicar cria a série logo abaixo, sem mexer na original',
      (tester) async {
    final sets = await _pumpEditor(
      tester,
      sets: [
        PrescribedSet(repsMin: 5, targetLoadKg: 60),
        PrescribedSet(repsMin: 12, targetLoadKg: 20),
      ],
    );

    await tester.tap(find.byKey(const Key('set-0-duplicate')));
    await tester.pumpAndSettle();

    expect(sets.length, 3);
    expect(sets[1].repsMin, 5);
    expect(sets[1].targetLoadKg, 60);
    // A cópia é independente: editar uma não altera a outra.
    expect(identical(sets[0], sets[1]), isFalse);
    expect(sets[2].repsMin, 12);
  });

  testWidgets('trocar a unidade move o número para o campo certo — 40 kg não vira RPE 40',
      (tester) async {
    final sets = await _pumpEditor(
      tester,
      sets: [PrescribedSet(repsMin: 8, targetLoadKg: 40)],
    );

    await tester.tap(find.byKey(const Key('set-0-unit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RPE').last);
    await tester.pumpAndSettle();

    expect(sets.single.targetUnit, TargetUnit.rpe);
    expect(sets.single.targetValue, 40);
    expect(sets.single.targetLoadKg, isNull);
  });

  testWidgets('a última série não pode ser removida — exercício sem série não publica',
      (tester) async {
    final sets = await _pumpEditor(
      tester,
      sets: [PrescribedSet(repsMin: 8), PrescribedSet(repsMin: 10)],
    );

    await tester.tap(find.byKey(const Key('set-1-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('set-1-remove')));
    await tester.pumpAndSettle();
    expect(sets.length, 1);

    await tester.tap(find.byKey(const Key('set-0-menu')));
    await tester.pumpAndSettle();
    final removeItem =
        tester.widget<PopupMenuItem<String>>(find.byKey(const Key('set-0-remove')));
    expect(removeItem.enabled, isFalse);
  });

  // Regressão: no celular (coluna única do builder) os 4 campos + 3 botões
  // numa fileira só deixavam cada campo com ~20 px — "8" virava "ε", "10"
  // virava "1" e os rótulos sumiam. 360 é a linha isolada num celular
  // pequeno; 296 é o que sobra dela dentro do card num celular de 360.
  for (final width in [360.0, 296.0]) {
    testWidgets('em $width px o valor digitado e o rótulo aparecem inteiros',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: LyTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: SetEditor(
                  sets: [PrescribedSet(targetLoadKg: 40)],
                  onChanged: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(tester.element(find.byType(SetEditor)));
      final typed = {
        'set-0-reps-min': ('8', l10n.builderRepsMin),
        'set-0-reps-max': ('10', l10n.builderRepsMax),
        'set-0-target': ('52.5', l10n.builderTargetKg),
        'set-0-rest': ('120', l10n.builderRestSeconds),
      };

      for (final MapEntry(key: key, value: (value, _)) in typed.entries) {
        await tester.enterText(find.byKey(Key(key)), value);
      }
      await tester.pumpAndSettle();

      // Nenhum RenderFlex estourou.
      expect(tester.takeException(), isNull);

      for (final MapEntry(key: key, value: (value, label)) in typed.entries) {
        final field = find.byKey(Key(key));
        expect(
          find.descendant(of: field, matching: find.text(value)),
          findsOneWidget,
          reason: '$key deveria mostrar "$value"',
        );

        // O campo de uma linha rola na horizontal quando o texto não cabe:
        // extensão de rolagem zero = valor inteiro visível, sem corte.
        final scroll = tester.state<ScrollableState>(
          find.descendant(of: field, matching: find.byType(Scrollable)),
        );
        expect(
          scroll.position.maxScrollExtent,
          0,
          reason: '"$value" não cabe em $key com $width px',
        );

        // Rótulo sem reticências: a largura desenhada comporta o texto todo.
        // Só em 360: a fonte de teste desenha cada glifo como um quadrado de
        // 1em (~1,8x a Manrope), então em 296 ela acusaria corte que o app
        // real não tem.
        if (width < 360) continue;
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: field, matching: find.text(label)),
        );
        expect(
          paragraph.getMaxIntrinsicWidth(double.infinity),
          lessThanOrEqualTo(paragraph.size.width + 0.5),
          reason: 'rótulo "$label" cortado em $key com $width px',
        );
      }
    });
  }
}
