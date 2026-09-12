import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart'
    hide Options;
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/checkin/data/checkin_repository.dart';
import 'package:lyfta/features/checkin/domain/checkin.dart';
import 'package:lyfta/features/checkin/presentation/checkin_sheet.dart';

/// Fake in-memory do plugin de secure storage — mesmo padrão do
/// `login_screen_test.dart`: o rascunho offline do check-in (P3.5 §2) usa
/// `flutter_secure_storage`, e sem isto o `flushDrafts` do boot do
/// controller bateria no platform channel de verdade.
class _FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> _values = {};

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      _values[key];

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _values[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    _values.remove(key);
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      _values.containsKey(key);

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) async =>
      Map.of(_values);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async => _values.clear();
}

class _FakeCheckinRepository extends CheckinRepository {
  _FakeCheckinRepository() : super(Dio());

  CheckinDraft? lastCreated;

  @override
  Future<WorkoutCheckin> create(CheckinDraft draft) async {
    lastCreated = draft;
    return WorkoutCheckin(
      id: 'checkin-1',
      studentId: 'student-1',
      sessionClientId: draft.sessionClientId,
      rating: draft.rating,
      difficulty: draft.difficulty,
      pain: draft.pain,
      painNotes: draft.painNotes,
      comment: draft.comment,
      createdAt: DateTime(2026, 9, 11),
    );
  }
}

class _Opened {
  const _Opened(this.repository, this.l10n);

  final _FakeCheckinRepository repository;
  final AppLocalizations l10n;
}

Future<_Opened> _pumpOpenSheet(WidgetTester tester) async {
  final repository = _FakeCheckinRepository();
  late AppLocalizations l10n;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [checkinRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: LyTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context);
            return Scaffold(
              body: Center(
                child: LyButton(
                  label: 'abrir',
                  onPressed: () =>
                      showCheckinSheet(context, sessionClientId: 'session-abc'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return _Opened(repository, l10n);
}

void main() {
  setUp(() {
    FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();
  });

  testWidgets(
      'valores de fábrica (nota e dificuldade 3, sem dor) enviam sem onde/dor',
      (tester) async {
    final opened = await _pumpOpenSheet(tester);
    final repository = opened.repository;
    final l10n = opened.l10n;

    await tester.ensureVisible(find.text(l10n.checkinSubmit));
    await tester.tap(find.text(l10n.checkinSubmit));
    await tester.pumpAndSettle();

    expect(repository.lastCreated, isNotNull);
    expect(repository.lastCreated!.sessionClientId, 'session-abc');
    expect(repository.lastCreated!.rating, 3);
    expect(repository.lastCreated!.difficulty, 3);
    expect(repository.lastCreated!.pain, PainLevel.none);
    expect(repository.lastCreated!.painNotes, '');
    expect(find.text(l10n.checkinSubmitted), findsOneWidget);
  });

  testWidgets('escolher nota, dificuldade e dor forte manda tudo com o onde',
      (tester) async {
    final opened = await _pumpOpenSheet(tester);
    final repository = opened.repository;
    final l10n = opened.l10n;

    // Nota 5 e dificuldade 1 — botões numerados, primeiro conjunto é a nota.
    await tester.tap(find.text('5').first);
    await tester.tap(find.text('1').last);

    await tester.tap(find.text(l10n.checkinPainStrong));
    await tester.pumpAndSettle();

    // O campo "onde" só aparece quando a dor não é "nenhuma", logo antes do
    // comentário — os dois únicos `TextField`s da folha nesse estado.
    expect(find.text(l10n.checkinPainWhereLabel), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'joelho direito');

    await tester.ensureVisible(find.text(l10n.checkinSubmit));
    await tester.tap(find.text(l10n.checkinSubmit));
    await tester.pumpAndSettle();

    expect(repository.lastCreated!.rating, 5);
    expect(repository.lastCreated!.difficulty, 1);
    expect(repository.lastCreated!.pain, PainLevel.strong);
    expect(repository.lastCreated!.painNotes, 'joelho direito');
  });
}
