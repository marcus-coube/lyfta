import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/workout/domain/today.dart';
import 'package:lyfta/features/workout/domain/workout_event.dart';
import 'package:lyfta/features/workout/presentation/rest_timer_controller.dart';
import 'package:lyfta/features/workout/presentation/session_controller.dart';
import 'package:lyfta/features/workout/presentation/session_player_screen.dart';
import 'package:lyfta/shared/domain/plan.dart';

class _FakeSession extends SessionController {
  _FakeSession(this.initial);
  final SessionState initial;
  var _n = 0;

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
    final cur = state.value!;
    final log = LocalSetLog(
      clientId: 'c${_n++}',
      sessionClientId: 's',
      exerciseId: exerciseId,
      setNo: setNo,
      performedAt: DateTime(2026),
      repsDone: repsDone,
      loadKg: loadKg,
      revises: revises,
    );
    // Mesmo contrato do store: o revisado sai, o revisor ocupa o lugar.
    state = AsyncData(
      SessionState(
        session: cur.session,
        today: cur.today,
        logs: [
          for (final l in cur.logs)
            if (l.clientId != revises) l,
          log,
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

void main() {
  late _FakeRest rest;

  Future<void> pumpPlayer(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final today = Today(
      status: TodayStatus.ready,
      day: WorkoutDay(
        label: 'A',
        blocks: [
          Block(
            blockType: BlockType.straight,
            restSeconds: 60,
            exercises: [
              BlockExercise(
                exerciseId: 'x',
                sets: [PrescribedSet(repsMax: 10), PrescribedSet(repsMax: 10)],
              ),
            ],
          ),
        ],
      ),
      previousLoads: const {},
      recentSessions: const [],
    );
    final initial = SessionState(
      session: LocalSession(
        clientId: 's',
        dayId: 'd',
        dayLabel: 'A',
        dayTitle: '',
        startedAt: DateTime.now().subtract(const Duration(minutes: 3)),
      ),
      today: today,
      logs: const [],
    );
    rest = _FakeRest();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionControllerProvider.overrideWith(() => _FakeSession(initial)),
          restTimerProvider.overrideWith(() => rest),
        ],
        child: MaterialApp(
          theme: LyTheme.dark(),
          locale: const Locale('pt'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SessionPlayerScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final logIcon = find.byIcon(Icons.check_circle_outline);
  final modalTitle = find.text('Treino concluído');

  testWidgets(
      'última série abre o modal sem descanso; Voltar não reabre; '
      'corrigir série também não', (tester) async {
    await pumpPlayer(tester);
    expect(find.byKey(const Key('session-clock')), findsOneWidget);

    // 1ª série: descansa, sem modal.
    await tester.tap(logIcon.first);
    await tester.pumpAndSettle();
    expect(rest.started, hasLength(1));
    expect(modalTitle, findsNothing);

    // Última série: nenhum descanso novo, modal aberto.
    await tester.tap(logIcon.first);
    await tester.pumpAndSettle();
    expect(rest.started, hasLength(1));
    expect(modalTitle, findsOneWidget);
    expect(find.byKey(const Key('complete-finish')), findsOneWidget);

    // Voltar: fecha, sessão segue aberta.
    await tester.tap(find.byKey(const Key('complete-back')));
    await tester.pumpAndSettle();
    expect(modalTitle, findsNothing);
    expect(find.byKey(const Key('session-clock')), findsOneWidget);
    // "Finalizar" da AppBar em destaque.
    expect(
      find.widgetWithText(FilledButton, 'Finalizar treino'),
      findsOneWidget,
    );

    // Corrigir uma série (revisão) não reabre o modal nem reinicia descanso.
    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '8');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(modalTitle, findsNothing);
    expect(rest.started, hasLength(1));
  });

  testWidgets('cronômetro avança sem reconstruir a lista', (tester) async {
    await pumpPlayer(tester);
    String clock() =>
        (tester.widget(find.byKey(const Key('session-clock'))) as Text).data!;
    final before = clock();
    expect(before, startsWith('0:03:'));
    // O relógio é o real (DateTime.now não é do fake async): espera de verdade.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(clock(), isNot(before));
    expect(find.byType(TextField), findsNWidgets(4));
  });
}
