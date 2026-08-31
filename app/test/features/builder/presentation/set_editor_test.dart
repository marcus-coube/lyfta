import 'package:flutter/material.dart';
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

    await tester.tap(find.byKey(const Key('set-1-remove')));
    await tester.pumpAndSettle();
    expect(sets.length, 1);

    final removeButton =
        tester.widget<IconButton>(find.byKey(const Key('set-0-remove')));
    expect(removeButton.onPressed, isNull);
  });
}
