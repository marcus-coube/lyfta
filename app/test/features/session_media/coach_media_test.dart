import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:duo/core/design_system/design_system.dart';
import 'package:duo/core/l10n/gen/app_localizations.dart';
import 'package:duo/core/push/push_deep_link.dart';
import 'package:duo/features/session_media/data/session_media_repository.dart';
import 'package:duo/features/session_media/domain/session_media.dart';
import 'package:duo/features/session_media/presentation/coach_media_viewer.dart';
import 'package:duo/features/session_media/presentation/coach_media_widgets.dart';

SessionMedia _m(
  String id, {
  DateTime? acked,
  DateTime? deleted,
  String session = 'sess1',
  String? exercise = 'Agachamento',
  DateTime? deleteAfter,
}) =>
    SessionMedia(
      id: id,
      contentType: 'image/jpeg',
      createdAt: DateTime(2026, 11, 16),
      deleteAfter: deleteAfter ?? DateTime(2026, 12, 16),
      studentId: 's1',
      sessionClientId: session,
      exerciseName: exercise,
      note: 'Dor no joelho?',
      ackedAt: acked,
      deletedAt: deleted,
      mediaUrl: deleted == null ? 'https://example.test/$id.jpg' : null,
    );

Widget _app(Widget home, {List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: LyTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('pt'),
        home: home,
      ),
    );

class _FakeRepo extends SessionMediaRepository {
  _FakeRepo({this.pending = const [], this.all = const []}) : super(Dio());

  List<SessionMedia> pending;
  List<SessionMedia> all;
  final calls = <String>[];
  final acks = <(String, String?)>[];

  @override
  Future<SessionMediaPage> listForCoach({
    required String studentId,
    bool pendingOnly = false,
    String? cursor,
    int? limit,
  }) async {
    calls.add('${pendingOnly ? 'pending' : 'all'}:$studentId:$cursor');
    return SessionMediaPage(items: pendingOnly ? pending : all);
  }

  @override
  Future<SessionMedia> ack(String id, {String? feedback}) async {
    acks.add((id, feedback));
    final old = all.firstWhere((m) => m.id == id);
    return old.withAck(
      _m(id, acked: DateTime(2026, 11, 17), deleteAfter: DateTime(2026, 11, 24)),
    );
  }
}

void main() {
  group('visualizador', () {
    testWidgets('aviso aparece antes do ack e nada é enviado até confirmar',
        (tester) async {
      final acks = <String?>[];
      await tester.pumpWidget(
        _app(
          CoachMediaViewer(
            media: _m('a'),
            onAck: (f) async {
              acks.add(f);
              return _m(
                'a',
                acked: DateTime(2026, 11, 17),
                deleteAfter: DateTime(2026, 11, 24),
              );
            },
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('viewer-warning')), findsOneWidget);
      expect(find.textContaining('7 dias'), findsOneWidget);
      expect(find.text('Agachamento'), findsOneWidget);
      expect(find.byKey(const Key('viewer-note')), findsOneWidget);
      expect(find.byKey(const Key('viewer-deleted-on')), findsNothing);
      expect(acks, isEmpty);

      await tester.tap(find.byKey(const Key('viewer-mark-seen')));
      await tester.pumpAndSettle();

      expect(acks, [null]);
      expect(find.byKey(const Key('viewer-warning')), findsNothing);
      expect(find.byKey(const Key('viewer-deleted-on')), findsOneWidget);
      expect(find.textContaining('Será apagada em'), findsOneWidget);
    });

    testWidgets('Responder envia o texto como feedback do ack', (tester) async {
      final acks = <String?>[];
      await tester.pumpWidget(
        _app(
          CoachMediaViewer(
            media: _m('a'),
            onAck: (f) async {
              acks.add(f);
              return _m('a', acked: DateTime(2026, 11, 17));
            },
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('viewer-reply')));
      await tester.pump();
      // Aviso continua visível enquanto digita, antes de confirmar.
      expect(find.byKey(const Key('viewer-warning')), findsOneWidget);
      final send = find.byKey(const Key('viewer-reply-send'));
      expect(tester.widget<LyButton>(send).onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('viewer-reply-field')),
        'Mantenha a coluna neutra',
      );
      await tester.pump();
      await tester.tap(send);
      await tester.pumpAndSettle();

      expect(acks, ['Mantenha a coluna neutra']);
      expect(find.byKey(const Key('viewer-deleted-on')), findsOneWidget);
    });

    testWidgets('falha no ack mostra o erro e mantém o aviso', (tester) async {
      await tester.pumpWidget(
        _app(
          CoachMediaViewer(
            media: _m('a'),
            onAck: (_) async => throw Exception('boom'),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('viewer-mark-seen')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('viewer-error')), findsOneWidget);
      expect(find.byKey(const Key('viewer-warning')), findsOneWidget);
    });
  });

  group('Para avaliar', () {
    testWidgets('lista as pendentes, abre o visualizador e some após o ack',
        (tester) async {
      final pending = _m('p1');
      final repo = _FakeRepo(pending: [pending], all: [pending]);
      await tester.pumpWidget(
        _app(
          const Scaffold(
            body: SingleChildScrollView(
              child: CoachMediaToEvaluate(studentId: 's1'),
            ),
          ),
          overrides: [sessionMediaRepositoryProvider.overrideWithValue(repo)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Para avaliar'), findsOneWidget);
      expect(find.byKey(const ValueKey('coach-media-p1')), findsOneWidget);
      // Uma chamada para as pendentes e uma para todas (um aluno, sem cursor).
      expect(repo.calls, ['pending:s1:null', 'all:s1:null']);

      await tester.tap(find.byKey(const ValueKey('coach-media-p1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('viewer-warning')), findsOneWidget);

      await tester.tap(find.byKey(const Key('viewer-mark-seen')));
      await tester.pumpAndSettle();
      expect(repo.acks, [('p1', null)]);

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('media-to-evaluate')), findsNothing);
    });

    testWidgets('sem pendentes a seção não aparece', (tester) async {
      final repo = _FakeRepo(all: [_m('x', acked: DateTime(2026, 11, 17))]);
      await tester.pumpWidget(
        _app(
          const Scaffold(body: CoachMediaToEvaluate(studentId: 's1')),
          overrides: [sessionMediaRepositoryProvider.overrideWithValue(repo)],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('media-to-evaluate')), findsNothing);
    });
  });

  group('mídias da sessão', () {
    testWidgets('vista mostra a data de exclusão; expirada fica esmaecida',
        (tester) async {
      final repo = _FakeRepo(
        all: [
          _m(
            'seen',
            acked: DateTime(2026, 11, 17),
            deleteAfter: DateTime(2026, 11, 24),
          ),
          _m('gone', deleted: DateTime(2026, 11, 20)),
          _m('other', session: 'sess2'),
        ],
      );
      await tester.pumpWidget(
        _app(
          const Scaffold(
            body: SingleChildScrollView(
              child: CoachSessionMedia(
                studentId: 's1',
                sessionClientId: 'sess1',
              ),
            ),
          ),
          overrides: [sessionMediaRepositoryProvider.overrideWithValue(repo)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('coach-media-other')), findsNothing);
      expect(
        tester.widget<Text>(
          find.byKey(const ValueKey('coach-media-status-seen')),
        ).data,
        contains('Será apagada em'),
      );
      expect(find.textContaining('Mídia expirada'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('coach-media-gone')),
          matching: find.byType(Opacity),
        ),
        findsOneWidget,
      );
    });
  });

  test('push session_media.new abre a ficha na aba Check-ins', () {
    final link = PushDeepLink.fromData({
      'type': 'session_media.new',
      'student_id': 's1',
      'media_id': 'm1',
      'tab': 'checkins',
    });
    expect(link.kind, PushDeepLinkKind.checkins);
    expect(link.studentId, 's1');
  });
}
