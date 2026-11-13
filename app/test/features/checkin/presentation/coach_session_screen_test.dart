import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/core/realtime/comms_socket.dart';
import 'package:lyfta/core/realtime/comms_socket_provider.dart';
import 'package:lyfta/features/checkin/data/checkin_repository.dart';
import 'package:lyfta/features/checkin/data/coach_session_repository.dart';
import 'package:lyfta/features/checkin/domain/checkin.dart';
import 'package:lyfta/features/checkin/domain/coach_session.dart';
import 'package:lyfta/features/checkin/presentation/coach_session_screen.dart';

class _CheckinsRepo extends CheckinRepository {
  _CheckinsRepo() : super(Dio());

  bool reviewed = false;

  @override
  Future<CheckinPage> list({
    required String studentId,
    String? cursor,
    int? limit,
  }) async =>
      CheckinPage(
        items: [
          WorkoutCheckin(
            id: 'c1',
            studentId: studentId,
            sessionClientId: 'sess1',
            rating: 5,
            difficulty: 2,
            pain: PainLevel.mild,
            painNotes: 'ombro',
            comment: 'Treino ótimo',
            createdAt: DateTime(2026, 9, 1, 18),
          ),
        ],
      );

  @override
  Future<WorkoutCheckin> review(String id) async {
    reviewed = true;
    final item = (await list(studentId: 's1')).items.first;
    return item.copyWith(reviewedBy: 'coach', reviewedAt: DateTime(2026, 9, 2));
  }
}

CoachSessionDetail _detail({int? durationSeconds = 3130}) {
  return CoachSessionDetail.fromJson({
    'client_id': 'sess1',
    'day_label': 'A',
    'plan_title': 'Força',
    'started_at': '2026-09-01T17:00:00Z',
    'finished_at': '2026-09-01T17:52:10Z',
    'duration_seconds': durationSeconds,
    'sets_count': 2,
    'reps_total': 18,
    'volume_kg': 180.0,
    'blocks': [
      {
        'block_type': 'straight',
        'exercises': [
          {
            'exercise_id': 'e1',
            'name': 'Supino reto',
            'sets': [
              {
                'set_no': 1,
                'label': 'Aquecimento',
                'variation_name': 'Pegada fechada',
                'prescribed': {
                  'reps_min': 8,
                  'reps_max': 10,
                  'target_load_kg': 20.0,
                  'target_unit': 'kg',
                },
                // Série corrigida: o valor é o corrigido.
                'done': {
                  'reps_done': 10,
                  'load_kg': 22.5,
                  'performed_at': '2026-09-01T17:10:00Z',
                  'revised': true,
                },
              },
              {
                'set_no': 2,
                'prescribed': {'reps_min': 8, 'reps_max': 8},
                'done': null,
              },
            ],
          },
        ],
      },
    ],
  });
}

class _SessionsRepo extends CoachSessionRepository {
  _SessionsRepo(this.detailResult) : super(Dio());

  final CoachSessionDetail detailResult;

  @override
  Future<CoachSessionDetail> detail(String studentId, String clientId) async =>
      detailResult;
}

Future<_CheckinsRepo> _pump(
  WidgetTester tester, {
  required Size size,
  CoachSessionDetail? detail,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final checkins = _CheckinsRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        checkinRepositoryProvider.overrideWithValue(checkins),
        coachSessionRepositoryProvider
            .overrideWithValue(_SessionsRepo(detail ?? _detail())),
        commsSocketProvider.overrideWithValue(
          CommsSocketService(
            readAccessToken: () async => null,
            refreshAccessToken: () async => null,
          ),
        ),
      ],
      child: MaterialApp(
        theme: LyTheme.dark(),
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const CoachSessionScreen(studentId: 's1', clientId: 'sess1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return checkins;
}

void main() {
  testWidgets('layout estreito: coluna única com série corrigida e não feita',
      (tester) async {
    await _pump(tester, size: const Size(400, 2400));

    expect(find.text('Treino A · Força'), findsOneWidget);
    expect(find.text('0:52:10'), findsOneWidget);
    expect(find.text('Treino ótimo'), findsOneWidget);
    expect(find.text('Supino reto'), findsOneWidget);
    expect(find.byKey(const Key('session_set_row_narrow')), findsNWidgets(2));
    expect(find.byKey(const Key('session_set_row_wide')), findsNothing);

    // Corrigida: valor novo + marca; chips de rótulo e variação (P9).
    expect(find.text('10 reps · 22,5 kg'), findsOneWidget);
    expect(find.byKey(const Key('session_set_revised')), findsOneWidget);
    expect(find.text('Aquecimento'), findsOneWidget);
    expect(find.text('Pegada fechada'), findsOneWidget);
    // Prescrito vem do formatador do player.
    expect(find.textContaining('8–10 reps'), findsOneWidget);
    // Não feita.
    expect(find.byKey(const Key('session_set_not_done')), findsOneWidget);
    expect(find.text('Não feita'), findsOneWidget);
  });

  testWidgets('layout largo: tabela com cabeçalho Série/Prescrito/Feito',
      (tester) async {
    await _pump(tester, size: const Size(1200, 1600));

    expect(find.byKey(const Key('session_set_row_wide')), findsNWidgets(2));
    expect(find.byKey(const Key('session_set_row_narrow')), findsNothing);
    expect(find.text('Série'), findsOneWidget);
    expect(find.text('Prescrito'), findsOneWidget);
    expect(find.text('Feito'), findsOneWidget);
    expect(find.byKey(const Key('session_set_revised')), findsOneWidget);
    expect(find.byKey(const Key('session_set_not_done')), findsOneWidget);
  });

  testWidgets('duração nula mostra traço e "Marcar como visto" funciona',
      (tester) async {
    final checkins = await _pump(
      tester,
      size: const Size(400, 2400),
      detail: _detail(durationSeconds: null),
    );

    expect(find.text('0:52:10'), findsNothing);
    expect(find.text('—'), findsOneWidget);

    await tester.tap(find.byKey(const Key('session_detail_review')));
    await tester.pumpAndSettle();

    expect(checkins.reviewed, isTrue);
    expect(find.byKey(const Key('session_detail_review')), findsNothing);
    expect(find.text('Visto'), findsOneWidget);
  });
}
