import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/http/api_exception.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/account/data/account_repository.dart';
import 'package:lyfta/features/account/presentation/account_controller.dart';
import 'package:lyfta/features/session_media/data/media_preparer.dart';
import 'package:lyfta/features/session_media/data/session_media_repository.dart';
import 'package:lyfta/features/session_media/domain/session_media.dart';
import 'package:lyfta/features/session_media/presentation/send_media_sheet.dart';
import 'package:lyfta/features/session_media/presentation/session_media_controller.dart';
import 'package:lyfta/features/session_media/presentation/session_media_section.dart';

const _session = 'session-abc';

SessionMedia _media(
  String id, {
  bool video = true,
  DateTime? acked,
  DateTime? deleted,
  String? exercise = 'Supino',
}) =>
    SessionMedia(
      id: id,
      contentType: video ? 'video/mp4' : 'image/jpeg',
      createdAt: DateTime(2026, 11, 16),
      deleteAfter: DateTime(2026, 12, 16),
      exerciseName: exercise,
      ackedAt: acked,
      deletedAt: deleted,
    );

class _FakeRepo extends SessionMediaRepository {
  _FakeRepo({this.items = const []}) : super(Dio());

  List<SessionMedia> items;
  Object? failWith;
  Completer<SessionMedia>? gate;
  int uploads = 0;
  final removed = <String>[];

  @override
  Future<List<SessionMedia>> list(String sessionClientId) async => items;

  @override
  Future<SessionMedia> upload({
    required String sessionClientId,
    required PreparedMedia media,
    String? exerciseId,
    String? exerciseName,
    String? note,
    CancelToken? cancelToken,
    void Function(double progress)? onProgress,
  }) async {
    uploads++;
    onProgress?.call(0.5);
    if (gate != null) return gate!.future;
    final error = failWith;
    if (error != null) throw error;
    return _media('new-$uploads', exercise: exerciseName);
  }

  @override
  Future<void> delete(String id) async {
    if (failWith != null) throw failWith!;
    removed.add(id);
  }
}

class _FakePreparer implements MediaPreparer {
  _FakePreparer(this.result);
  PreparedMedia? result;

  @override
  Future<PreparedMedia?> pick({
    required bool video,
    required ImageSource source,
  }) async =>
      result;
}

PreparedMedia _file(int size) => PreparedMedia(
      bytes: Uint8List(size),
      contentType: 'video/mp4',
      isVideo: true,
      name: 'treino.mp4',
    );

ConsentStatus _consent({bool photos = true}) => ConsentStatus(
      termsVersion: 'v',
      required: const [],
      granted: [if (photos) ConsentPurpose.progressPhotos],
      needsConsent: false,
    );

Future<void> _openSheet(
  WidgetTester tester, {
  required _FakeRepo repo,
  Future<ConsentStatus> Function()? consent,
  PreparedMedia? picked,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionMediaRepositoryProvider.overrideWithValue(repo),
        mediaPreparerProvider.overrideWithValue(_FakePreparer(picked)),
        consentStatusProvider
            .overrideWith((ref) => (consent ?? () async => _consent())()),
      ],
      child: MaterialApp(
        locale: const Locale('pt', 'BR'),
        theme: LyTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => Column(
              children: [
                // Mantém o provider vivo, como o player faz.
                const SessionMediaSection(sessionClientId: _session),
                TextButton(
                  onPressed: () => showSendMediaSheet(
                    context,
                    sessionClientId: _session,
                    exerciseId: 'ex-1',
                    exerciseName: 'Supino',
                  ),
                  child: const Text('abrir'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  group('folha de envio', () {
    testWidgets('mostra o aviso de limite e retenção antes de escolher',
        (tester) async {
      await _openSheet(tester, repo: _FakeRepo());
      final warning = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('media-warning')),
          matching: find.byType(Text),
        ),
      );
      expect(warning.data, contains('20 MB'));
      expect(warning.data, contains('7 dias'));
      expect(warning.data, contains('30 dias'));
      expect(find.text('Exercício: Supino'), findsOneWidget);
      expect(find.byKey(const Key('media-camera')), findsOneWidget);
      // Sem arquivo escolhido não há o que enviar.
      expect(
        tester.widget<LyButton>(find.byKey(const Key('media-send'))).onPressed,
        isNull,
      );
    });

    testWidgets('arquivo acima de 20 MB é recusado com o tamanho e nada sobe',
        (tester) async {
      final repo = _FakeRepo();
      await _openSheet(
        tester,
        repo: repo,
        picked: _file(21 * 1024 * 1024),
      );
      await tester.tap(find.byKey(const Key('media-gallery')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('media-error'))).data,
        contains('21,0 MB'),
      );
      expect(find.byKey(const Key('media-picked')), findsNothing);
      expect(repo.uploads, 0);
    });

    testWidgets('com 3 mídias na sessão mostra o limite e esconde a câmera',
        (tester) async {
      await _openSheet(
        tester,
        repo: _FakeRepo(items: [_media('a'), _media('b'), _media('c')]),
      );
      expect(find.byKey(const Key('media-limit')), findsOneWidget);
      expect(find.byKey(const Key('media-camera')), findsNothing);
    });

    testWidgets('sem consentimento leva à privacidade em vez da câmera',
        (tester) async {
      await _openSheet(
        tester,
        repo: _FakeRepo(),
        consent: () async => _consent(photos: false),
      );
      expect(find.byKey(const Key('media-no-consent')), findsOneWidget);
      expect(find.byKey(const Key('media-open-privacy')), findsOneWidget);
      expect(find.byKey(const Key('media-camera')), findsNothing);
      expect(find.byKey(const Key('media-warning')), findsOneWidget);
    });

    testWidgets('offline explica que precisa de conexão', (tester) async {
      await _openSheet(
        tester,
        repo: _FakeRepo(),
        consent: () async => throw const ApiException.network(),
      );
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('media-consent-error')),
                matching: find.byType(Text),
              ),
            )
            .data,
        contains('precisa de internet'),
      );
      expect(find.byKey(const Key('media-camera')), findsNothing);
    });

    testWidgets('enviar fecha a folha na hora e o upload segue em segundo plano',
        (tester) async {
      final repo = _FakeRepo()..gate = Completer<SessionMedia>();
      await _openSheet(tester, repo: repo, picked: _file(1024));
      await tester.tap(find.byKey(const Key('media-camera')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('media-picked')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('media-note')), 'minha técnica');
      await tester.tap(find.byKey(const Key('media-send')));
      await tester.pumpAndSettle();

      // Folha fechada, envio em curso e a lista já mostra o progresso.
      expect(find.byKey(const Key('media-send')), findsNothing);
      expect(repo.uploads, 1);
      expect(find.byKey(const Key('media-upload')), findsOneWidget);
      expect(find.text('Enviando… 50%'), findsOneWidget);

      repo.gate!.complete(_media('done'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('media-upload')), findsNothing);
      expect(find.byKey(const ValueKey('media-done')), findsOneWidget);
    });
  });

  group('Enviados neste treino', () {
    Future<void> pumpSection(WidgetTester tester, _FakeRepo repo) async {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [sessionMediaRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            locale: const Locale('pt', 'BR'),
            theme: LyTheme.dark(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: SessionMediaSection(sessionClientId: _session),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('some quando não há nada; mostra enviado, visto e expirado',
        (tester) async {
      await pumpSection(tester, _FakeRepo());
      expect(find.byKey(const Key('session-media-section')), findsNothing);

      await pumpSection(
        tester,
        _FakeRepo(
          items: [
            _media('a'),
            _media('b', acked: DateTime(2026, 11, 17)),
            _media('c', deleted: DateTime(2026, 11, 20), video: false),
          ],
        ),
      );
      // A troca de repositório recria o provider no novo ProviderScope.
      expect(find.byKey(const Key('session-media-section')), findsOneWidget);
      String status(String id) =>
          tester.widget<Text>(find.byKey(ValueKey('media-status-$id'))).data!;
      expect(status('a'), startsWith('Enviado'));
      expect(status('a'), contains('16/12'));
      expect(status('b'), startsWith('Visto pelo professor'));
      expect(status('c'), 'Mídia expirada');
      // Expirada não tem o que remover.
      expect(find.byKey(const ValueKey('media-remove-c')), findsNothing);
    });

    testWidgets('remover chama o servidor e tira da lista', (tester) async {
      final repo = _FakeRepo(items: [_media('a'), _media('b')]);
      await pumpSection(tester, repo);
      await tester.tap(find.byKey(const ValueKey('media-remove-a')));
      await tester.pumpAndSettle();
      expect(repo.removed, ['a']);
      expect(find.byKey(const ValueKey('media-a')), findsNothing);
      expect(find.byKey(const ValueKey('media-b')), findsOneWidget);
    });

    testWidgets('falha de remoção mostra a mensagem e mantém o item',
        (tester) async {
      final repo = _FakeRepo(items: [_media('a')])
        ..failWith = const ApiException.network();
      await pumpSection(tester, repo);
      await tester.tap(find.byKey(const ValueKey('media-remove-a')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byKey(const ValueKey('media-a')), findsOneWidget);
    });
  });

  group('controller', () {
    ProviderContainer container(_FakeRepo repo) {
      final c = ProviderContainer(
        overrides: [sessionMediaRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('falha no upload mantém o arquivo para tentar de novo', () async {
      final repo = _FakeRepo()
        ..failWith = const ApiException(code: 'session_media_limit', params: {'max': 3});
      final c = container(repo);
      final notifier = c.read(sessionMediaProvider(_session).notifier);

      await notifier.start(media: _file(10), exerciseName: 'Supino');
      var state = c.read(sessionMediaProvider(_session));
      expect(state.upload?.failed, isTrue);
      expect(state.items, isEmpty);

      repo.failWith = null;
      await notifier.retry();
      state = c.read(sessionMediaProvider(_session));
      expect(state.upload, isNull);
      expect(state.items, hasLength(1));
      expect(repo.uploads, 2);
    });

    test('um envio por vez e cancelar derruba o que falhou', () async {
      final repo = _FakeRepo()..gate = Completer<SessionMedia>();
      final c = container(repo);
      final notifier = c.read(sessionMediaProvider(_session).notifier);

      final first = notifier.start(media: _file(10));
      await notifier.start(media: _file(10)); // ignorado: já há envio
      expect(repo.uploads, 1);
      repo.gate!.complete(_media('x'));
      await first;

      repo.failWith = const ApiException.network();
      repo.gate = null;
      await notifier.start(media: _file(10));
      expect(c.read(sessionMediaProvider(_session)).upload?.failed, isTrue);
      notifier.cancel();
      expect(c.read(sessionMediaProvider(_session)).upload, isNull);
    });
  });

  test('tipo do vídeo vem da extensão ou do MIME', () {
    expect(videoContentTypeFor('a.MOV'), 'video/quicktime');
    expect(videoContentTypeFor('a.webm'), 'video/webm');
    expect(videoContentTypeFor('a.bin', mime: 'video/quicktime'), 'video/quicktime');
    expect(videoContentTypeFor('a.mp4'), 'video/mp4');
  });
}
