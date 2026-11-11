import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/core/realtime/comms_socket.dart';
import 'package:lyfta/core/realtime/comms_socket_provider.dart';
import 'package:lyfta/features/checkin/data/checkin_repository.dart';
import 'package:lyfta/features/checkin/domain/checkin.dart';
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

/// Duas páginas: a primeira com cursor, a segunda sem.
class _PagedRepository extends CheckinRepository {
  _PagedRepository() : super(Dio());

  final cursors = <String?>[];

  @override
  Future<CheckinPage> list({
    required String studentId,
    String? cursor,
    int? limit,
  }) async {
    cursors.add(cursor);
    if (cursor == null) {
      return CheckinPage(
        items: [for (var i = 0; i < 3; i++) _checkin(i)],
        nextCursor: 'p2',
      );
    }
    return CheckinPage(items: [_checkin(10), _checkin(11)]);
  }
}

void main() {
  testWidgets('fila acima de uma página: botão carrega a seguinte e some',
      (tester) async {
    final repository = _PagedRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          checkinRepositoryProvider.overrideWithValue(repository),
          commsSocketProvider.overrideWithValue(
            CommsSocketService(
              readAccessToken: () async => null,
              refreshAccessToken: () async => null,
            ),
          ),
        ],
        child: MaterialApp(
          theme: LyTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: CoachCheckinsTab(studentId: 's1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final more = find.byKey(const Key('checkins_load_more'));
    await tester.scrollUntilVisible(more, 200);
    expect(more, findsOneWidget);

    await tester.tap(more);
    await tester.pumpAndSettle();

    expect(repository.cursors, [null, 'p2']);
    expect(find.byKey(const Key('checkins_load_more')), findsNothing);
    expect(find.byType(LyCard), findsNWidgets(5));
  });
}
