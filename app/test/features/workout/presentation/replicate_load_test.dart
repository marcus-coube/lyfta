import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:duo/core/design_system/design_system.dart';
import 'package:duo/core/l10n/gen/app_localizations.dart';
import 'package:duo/features/workout/domain/block_runner.dart';
import 'package:duo/features/workout/domain/today.dart';
import 'package:duo/features/workout/domain/workout_event.dart';
import 'package:duo/features/workout/presentation/exercise_fields.dart';
import 'package:duo/features/workout/presentation/rest_timer_controller.dart';
import 'package:duo/features/workout/presentation/session_controller.dart';
import 'package:duo/features/workout/presentation/widgets/block_card.dart';
import 'package:duo/features/workout/presentation/widgets/set_row.dart';
import 'package:duo/shared/domain/plan.dart';

Widget _app(Widget child) => MaterialApp(
      theme: LyTheme.dark(),
      locale: const Locale('pt'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

LocalSetLog _log(String ex, int setNo) => LocalSetLog(
      clientId: 'c$ex$setNo',
      sessionClientId: 's',
      exerciseId: ex,
      setNo: setNo,
      performedAt: DateTime(2026),
      repsDone: 10,
      loadKg: 20,
    );

/// Quatro séries de um exercício, com [logged] já registradas.
Widget _straight(ExerciseFields fields, Set<int> logged) {
  fields.bind(name: 'Supino', isLogged: logged.contains);
  return Column(
    children: [
      for (var i = 1; i <= 4; i++)
        SetRow(
          setNo: i,
          prescribed: PrescribedSet(repsMax: 10),
          logged: logged.contains(i) ? _log('A', i) : null,
          fields: fields,
          onLog: (_, __, ___) async {},
        ),
    ],
  );
}

String _load(WidgetTester tester, int index) =>
    tester.widget<TextField>(find.byType(TextField).at(index)).controller!.text;

void main() {
  testWidgets('digitar 40 na 1ª e confirmar deixa 40 nas 4 séries', (tester) async {
    final fields = ExerciseFields(exerciseName: 'Supino');
    addTearDown(fields.dispose);
    await tester.pumpWidget(_app(_straight(fields, {})));

    expect(find.byKey(const Key('replicate-offer')), findsNothing);
    await tester.enterText(find.byType(TextField).at(1), '40');
    await tester.pump();
    expect(find.byKey(const Key('replicate-offer')), findsOneWidget);

    await tester.tap(find.byKey(const Key('replicate-offer')));
    await tester.pumpAndSettle();
    expect(find.text('Replicar 40 kg para todas as séries de Supino?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('replicate-confirm')));
    await tester.pumpAndSettle();

    for (var i = 0; i < 4; i++) {
      expect(_load(tester, 2 * i + 1), '40');
    }
    // Reps intactas e oferta usada: não volta nesta sessão.
    expect(_load(tester, 0), '10');
    expect(find.byKey(const Key('replicate-offer')), findsNothing);
    await tester.enterText(find.byType(TextField).at(3), '45');
    await tester.pump();
    expect(find.byKey(const Key('replicate-offer')), findsNothing);
  });

  testWidgets('com a 1ª registrada, digitar na 2ª replica só para a 3ª e 4ª',
      (tester) async {
    final fields = ExerciseFields(exerciseName: 'Supino');
    addTearDown(fields.dispose);
    final logged = {1};
    await tester.pumpWidget(_app(_straight(fields, logged)));

    // Série 1 registrada não tem campos: a 2ª é o primeiro par de TextFields.
    expect(find.byType(TextField), findsNWidgets(6));
    await tester.enterText(find.byType(TextField).at(1), '40');
    await tester.pump();
    await tester.tap(find.byKey(const Key('replicate-offer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('replicate-confirm')));
    await tester.pumpAndSettle();

    expect(_load(tester, 1), '40');
    expect(_load(tester, 3), '40');
    expect(_load(tester, 5), '40');
    // A série registrada continua mostrando o que foi feito.
    expect(find.text('10 reps · 20 kg'), findsOneWidget);
  });

  testWidgets('dispensar some com a oferta e não altera nenhum campo',
      (tester) async {
    final fields = ExerciseFields(exerciseName: 'Supino');
    addTearDown(fields.dispose);
    await tester.pumpWidget(_app(_straight(fields, {})));

    await tester.enterText(find.byType(TextField).at(1), '40');
    await tester.pump();
    await tester.tap(find.byKey(const Key('replicate-dismiss')));
    await tester.pump();

    expect(find.byKey(const Key('replicate-offer')), findsNothing);
    expect(_load(tester, 3), '');
  });

  testWidgets('em bi-set replicar no exercício A não mexe no B', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    BlockExercise ex(String id) => BlockExercise(
          exerciseId: id,
          sets: [PrescribedSet(repsMax: 10), PrescribedSet(repsMax: 10)],
        );
    final block = Block(
      blockType: BlockType.superset,
      restSeconds: 90,
      exercises: [ex('A'), ex('B')],
    );
    final today = Today(
      status: TodayStatus.ready,
      day: WorkoutDay(label: 'A', blocks: [block]),
      previousLoads: const {},
      recentSessions: const [],
    );
    final state = SessionState(
      session: LocalSession(
        clientId: 's',
        dayId: 'd',
        dayLabel: 'A',
        dayTitle: '',
        startedAt: DateTime(2026),
      ),
      today: today,
      logs: const [],
    );
    final runner = BlockRunner.fromRuns(today.runs).single;
    final registry = ExerciseFieldsRegistry();
    addTearDown(registry.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          restTimerProvider.overrideWith(() => _NoRest()),
        ],
        child: _app(BlockCard(runner: runner, state: state, registry: registry)),
      ),
    );
    await tester.pumpAndSettle();

    // Ordem visual: A1, B1, A2, B2 — cada série tem 2 campos (reps, carga).
    await tester.enterText(find.byType(TextField).at(1), '40');
    await tester.pump();
    await tester.tap(find.byKey(const Key('replicate-offer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('replicate-confirm')));
    await tester.pumpAndSettle();

    expect(_load(tester, 1), '40'); // A1
    expect(_load(tester, 3), ''); // B1
    expect(_load(tester, 5), '40'); // A2
    expect(_load(tester, 7), ''); // B2
  });
}

class _NoRest extends RestTimerController {
  @override
  RestState? build() => null;
}
