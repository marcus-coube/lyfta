import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/http/api_exception.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/core/realtime/comms_socket.dart';
import 'package:lyfta/core/realtime/comms_socket_provider.dart';
import 'package:lyfta/features/checkin/data/checkin_repository.dart';
import 'package:lyfta/features/checkin/data/coach_session_repository.dart';
import 'package:lyfta/features/checkin/domain/checkin.dart';
import 'package:lyfta/features/checkin/domain/coach_session.dart';
import 'package:lyfta/features/checkin/presentation/coach_checkins_tab.dart';

WorkoutCheckin _checkin(int n) => WorkoutCheckin(
      id: 'c$n',
      studentId: 's1',
      sessionClientId: 'sess$n',
      rating: 4,
      difficulty: 3,
      pain: PainLevel.none,
      createdAt: DateTime(2026, 9, 1).add(Duration(days: n)),
    );

class _CheckinsRepo extends CheckinRepository {
  _CheckinsRepo() : super(Dio());

  @override
  Future<CheckinPage> list({
    required String studentId,
    String? cursor,
    int? limit,
  }) async =>
      CheckinPage(items: [_checkin(0), _checkin(1)]);
}

final _session = CoachSession(
  clientId: 'sess0',
  dayLabel: 'A',
  planTitle: 'Força',
  startedAt: DateTime(2026, 9, 1),
  setsCount: 12,
  repsTotal: 96,
  volumeKg: 4200,
  durationSeconds: 3130,
);

class _SessionsRepo extends CoachSessionRepository {
  _SessionsRepo({this.failFirst = false}) : super(Dio());

  final bool failFirst;
  final calls = <List<String>>[];

  @override
  Future<Map<String, CoachSession>> lookup(
    String studentId,
    List<String> clientIds,
  ) async {
    calls.add(clientIds);
    if (failFirst && calls.length == 1) throw const ApiException.network();
    // Só a sess0 chegou ao servidor; a sess1 ainda está na fila do aluno.
    return {'sess0': _session};
  }
}

Future<void> _pump(WidgetTester tester, _SessionsRepo sessions) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) =>
            const Scaffold(body: CoachCheckinsTab(studentId: 's1')),
      ),
      GoRoute(
        path: '/students/:id/sessions/:clientId',
        builder: (_, state) =>
            Text('detalhe ${state.pathParameters['clientId']}'),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        checkinRepositoryProvider.overrideWithValue(_CheckinsRepo()),
        coachSessionRepositoryProvider.overrideWithValue(sessions),
        commsSocketProvider.overrideWithValue(
          CommsSocketService(
            readAccessToken: () async => null,
            refreshAccessToken: () async => null,
          ),
        ),
      ],
      child: MaterialApp.router(
        theme: LyTheme.dark(),
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('card com sessão mostra treino e métricas; sem sessão avisa',
      (tester) async {
    final sessions = _SessionsRepo();
    await _pump(tester, sessions);

    expect(sessions.calls, [
      ['sess0', 'sess1'],
    ]);
    expect(find.text('Treino A · Força'), findsOneWidget);
    expect(
      find.text('12 séries · 96 reps · 4.200 kg · 0:52:10'),
      findsOneWidget,
    );
    expect(find.text('Treino ainda não sincronizado'), findsOneWidget);
    expect(find.byKey(const Key('checkin_session_failed')), findsNothing);
  });

  testWidgets('falha do lookup não derruba a lista e tem retry',
      (tester) async {
    final sessions = _SessionsRepo(failFirst: true);
    await _pump(tester, sessions);

    // A lista segue de pé, só sem a linha do treino.
    expect(find.byType(LyCard), findsNWidgets(2));
    expect(find.byKey(const Key('checkin_session_failed')), findsNWidgets(2));
    expect(find.text('Treino A · Força'), findsNothing);

    await tester.tap(find.byKey(const Key('checkin_session_retry')).first);
    await tester.pumpAndSettle();

    expect(sessions.calls.length, 2);
    expect(find.text('Treino A · Força'), findsOneWidget);
    expect(find.byKey(const Key('checkin_session_failed')), findsNothing);
  });

  testWidgets('tocar no card abre o detalhe da sessão', (tester) async {
    await _pump(tester, _SessionsRepo());

    await tester.tap(find.text('Treino A · Força'));
    await tester.pumpAndSettle();

    expect(find.text('detalhe sess0'), findsOneWidget);
  });
}
