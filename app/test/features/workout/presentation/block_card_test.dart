import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/workout/domain/block_runner.dart';
import 'package:lyfta/features/workout/domain/today.dart';
import 'package:lyfta/features/workout/domain/workout_event.dart';
import 'package:lyfta/features/workout/presentation/rest_timer_controller.dart';
import 'package:lyfta/features/workout/presentation/session_controller.dart';
import 'package:lyfta/features/workout/presentation/widgets/block_card.dart';
import 'package:lyfta/shared/domain/plan.dart';

class _FakeSession extends SessionController {
  _FakeSession(this.initial);
  final SessionState initial;
  final calls = <String>[];

  @override
  Future<SessionState?> build() async => initial;

  @override
  Future<void> logSet({
    required String exerciseId,
    required int setNo,
    int? repsDone,
    double? loadKg,
    String? revises,
  }) async {
    calls.add('$exerciseId$setNo');
    final cur = state.value!;
    state = AsyncData(
      SessionState(
        session: cur.session,
        today: cur.today,
        logs: [
          ...cur.logs,
          LocalSetLog(
            clientId: 'c$exerciseId$setNo',
            sessionClientId: 's',
            exerciseId: exerciseId,
            setNo: setNo,
            performedAt: DateTime(2026),
            repsDone: repsDone,
            loadKg: loadKg,
          ),
        ],
      ),
    );
  }
}

class _FakeRest extends RestTimerController {
  final started = <Duration>[];

  @override
  RestState? build() => null;

  @override
  void start({
    required Duration rest,
    required String label,
    required String notificationTitle,
    required String notificationBody,
  }) =>
      started.add(rest);
}

BlockExercise _ex(String id) => BlockExercise(
      exerciseId: id,
      sets: [PrescribedSet(repsMax: 10), PrescribedSet(repsMax: 10)],
    );

void main() {
  testWidgets('cartão de superset conduz por rodada e descansa só ao fim dela',
      (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final block = Block(
      blockType: BlockType.superset,
      restSeconds: 90,
      exercises: [_ex('A'), _ex('B')],
    );
    final day = WorkoutDay(label: 'A', blocks: [block]);
    final today = Today(
      status: TodayStatus.ready,
      day: day,
      previousLoads: const {},
      recentSessions: const [],
    );
    final initial = SessionState(
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
    final fake = _FakeSession(initial);
    final rest = _FakeRest();
    final runner = BlockRunner.fromRuns(today.runs).single;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionControllerProvider.overrideWith(() => fake),
          restTimerProvider.overrideWith(() => rest),
        ],
        child: MaterialApp(
          theme: LyTheme.dark(),
          locale: const Locale('pt'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Consumer(
                builder: (context, ref, _) {
                  final st = ref.watch(sessionControllerProvider).value;
                  if (st == null) return const SizedBox.shrink();
                  return BlockCard(runner: runner, state: st);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rodada 1 de 2'), findsOneWidget);
    expect(find.text('Rodada 2 de 2'), findsOneWidget);
    expect(find.text('Bi-set'), findsOneWidget);

    // Ordem visual: A1, B1, A2, B2.
    double y(String key) => tester.getTopLeft(find.byKey(ValueKey(key))).dy;
    expect(y('block-step-A-1') < y('block-step-B-1'), isTrue);
    expect(y('block-step-B-1') < y('block-step-A-2'), isTrue);
    expect(y('block-step-A-2') < y('block-step-B-2'), isTrue);
    expect(find.text('Agora'), findsOneWidget);

    Future<void> tapDone(String key) async {
      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byIcon(Icons.check_circle_outline),
        ),
      );
      await tester.pumpAndSettle();
    }

    await tapDone('block-step-A-1');
    await tapDone('block-step-B-1');
    expect(fake.calls, ['A1', 'B1']);
    // A1 -> B1 sem descanso; B1 fecha a rodada com o descanso do bloco.
    expect(rest.started, [Duration.zero, const Duration(seconds: 90)]);
  });
}
