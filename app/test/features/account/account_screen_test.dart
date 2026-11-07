import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/auth/auth_controller.dart';
import 'package:lyfta/core/auth/auth_state.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/http/api_exception.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/account/data/account_repository.dart';
import 'package:lyfta/features/account/presentation/account_screen.dart';
import 'package:lyfta/features/checkin/data/checkin_draft_storage.dart';
import 'package:lyfta/features/workout/data/local/memory_workout_store.dart';
import 'package:lyfta/features/workout/data/workout_repository.dart';

class _TestAuth extends AuthController {
  bool deletionCompleted = false;
  final consentCalls = <bool>[];

  @override
  AuthState build() => AuthState.authenticated(
        roles: {UserRole.student},
        tenantId: 'tenant-1',
        userId: 'user-1',
      );

  @override
  Future<void> applyConsentResult({
    required String? accessToken,
    required bool needsConsent,
  }) async {
    consentCalls.add(needsConsent);
  }

  @override
  Future<void> completeAccountDeletion() async {
    deletionCompleted = true;
  }
}

class _FakeAccountRepository extends AccountRepository {
  _FakeAccountRepository({this.deleteError})
      : super(Dio(), termsVersion: 'v-teste');

  final ApiException? deleteError;
  var photosGranted = true;
  final puts = <Map<String, bool>>[];
  final deletedWith = <String>[];

  ConsentStatus get _status => ConsentStatus(
        termsVersion: 'v-teste',
        required: const ['terms', 'health_data'],
        granted: ['terms', 'health_data', if (photosGranted) 'progress_photos'],
        needsConsent: false,
        accessToken: 'token',
      );

  @override
  Future<ConsentStatus> consents() async => _status;

  @override
  Future<ConsentStatus> putConsents(Map<String, bool> consents) async {
    puts.add(consents);
    photosGranted = consents['progress_photos'] ?? photosGranted;
    return _status;
  }

  @override
  Future<void> deleteMe(String password) async {
    deletedWith.add(password);
    if (deleteError != null) throw deleteError!;
  }
}

class _FakeDrafts extends CheckinDraftStorage {
  bool cleared = false;

  @override
  Future<void> clear(String userId) async => cleared = true;
}

class _Harness {
  _Harness(this.auth, this.repository, this.drafts, this.store);

  final _TestAuth auth;
  final _FakeAccountRepository repository;
  final _FakeDrafts drafts;
  final MemoryWorkoutStore store;
}

Future<_Harness> _pump(WidgetTester tester, {ApiException? deleteError}) async {
  final harness = _Harness(
    _TestAuth(),
    _FakeAccountRepository(deleteError: deleteError),
    _FakeDrafts(),
    MemoryWorkoutStore(),
  );
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => harness.auth),
        accountRepositoryProvider.overrideWithValue(harness.repository),
        checkinDraftStorageProvider.overrideWithValue(harness.drafts),
        workoutLocalStoreProvider.overrideWithValue(harness.store),
      ],
      child: MaterialApp(
        theme: LyTheme.dark(),
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AccountScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('pt'));

  testWidgets('desligar as fotos revoga só progress_photos', (tester) async {
    final h = await _pump(tester);

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('account_photos_switch')),
          )
          .value,
      isTrue,
    );
    await tester.tap(find.byKey(const Key('account_photos_switch')));
    await tester.pumpAndSettle();

    expect(h.repository.puts, [
      {'progress_photos': false},
    ]);
    expect(h.auth.consentCalls, [false]);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('account_photos_switch')),
          )
          .value,
      isFalse,
    );
  });

  testWidgets('excluir conta pede a senha, apaga no servidor e limpa o device',
      (tester) async {
    final h = await _pump(tester);

    await tester.tap(find.byKey(const Key('account_delete')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.accountDeleteDialogTitle), findsOneWidget);

    // Sem senha o botão fica desabilitado.
    TextButton confirm() =>
        tester.widget<TextButton>(find.byKey(const Key('delete_confirm')));
    expect(confirm().onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('delete_password')),
      'SenhaAluno123!',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('delete_confirm')));
    await tester.pumpAndSettle();

    expect(h.repository.deletedWith, ['SenhaAluno123!']);
    expect(h.drafts.cleared, isTrue);
    expect(h.auth.deletionCompleted, isTrue);
  });

  testWidgets('senha errada mostra o erro e não limpa nada', (tester) async {
    final h = await _pump(
      tester,
      deleteError:
          const ApiException(code: 'invalid_password', statusCode: 403),
    );

    await tester.tap(find.byKey(const Key('account_delete')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('delete_password')), 'errada');
    await tester.pump();
    await tester.tap(find.byKey(const Key('delete_confirm')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.errorInvalidPassword), findsOneWidget);
    expect(h.drafts.cleared, isFalse);
    expect(h.auth.deletionCompleted, isFalse);
  });
}
