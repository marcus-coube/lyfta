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
import 'package:lyfta/features/consent/presentation/consent_screen.dart';

/// Auth sem storage nem rede: nasce autenticado e com o gate de consentimento
/// armado, e registra o que a tela aplicou.
class _TestAuth extends AuthController {
  _TestAuth(this.roles);

  final Set<UserRole> roles;
  bool? needsConsentApplied;

  @override
  AuthState build() => AuthState.authenticated(
        roles: roles,
        tenantId: 'tenant-1',
        userId: 'user-1',
        consentPending: true,
      );

  @override
  Future<void> applyConsentResult({
    required String? accessToken,
    required bool needsConsent,
  }) async {
    needsConsentApplied = needsConsent;
    state = state.copyWith(consentPending: needsConsent);
  }
}

class _FakeAccountRepository extends AccountRepository {
  _FakeAccountRepository({this.error}) : super(Dio(), termsVersion: 'v-teste');

  final ApiException? error;
  final puts = <Map<String, bool>>[];

  @override
  Future<ConsentStatus> putConsents(Map<String, bool> consents) async {
    if (error != null) throw error!;
    puts.add(consents);
    return const ConsentStatus(
      termsVersion: 'v-teste',
      required: ['terms', 'health_data'],
      granted: ['terms', 'health_data'],
      needsConsent: false,
      accessToken: 'novo-token',
    );
  }
}

Future<(_TestAuth, _FakeAccountRepository)> _pump(
  WidgetTester tester, {
  Set<UserRole> roles = const {UserRole.student},
  ApiException? error,
}) async {
  final auth = _TestAuth(roles);
  final repository = _FakeAccountRepository(error: error);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => auth),
        accountRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: LyTheme.dark(),
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ConsentScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (auth, repository);
}

Finder _submit(AppLocalizations l10n) =>
    find.widgetWithText(LyButton, l10n.consentSubmit);

bool _enabled(WidgetTester tester, Finder button) =>
    tester.widget<LyButton>(button).onPressed != null;

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('pt'));

  testWidgets('aluno só continua com os termos E os dados de saúde',
      (tester) async {
    final (auth, repository) = await _pump(tester);

    expect(_enabled(tester, _submit(l10n)), isFalse);

    await _tap(tester, 'consent_terms');
    expect(
      _enabled(tester, _submit(l10n)),
      isFalse,
      reason: 'faltam os dados de saúde',
    );

    await _tap(tester, 'consent_health_data');
    expect(_enabled(tester, _submit(l10n)), isTrue);

    await tester.tap(_submit(l10n));
    await tester.pumpAndSettle();

    expect(repository.puts, [
      {'terms': true, 'health_data': true, 'progress_photos': false},
    ]);
    expect(auth.needsConsentApplied, isFalse);
  });

  testWidgets('fotos de evolução são opcionais e vão separadas',
      (tester) async {
    final (_, repository) = await _pump(tester);

    await _tap(tester, 'consent_terms');
    await _tap(tester, 'consent_health_data');
    await _tap(tester, 'consent_progress_photos');
    await tester.tap(_submit(l10n));
    await tester.pumpAndSettle();

    expect(repository.puts.single['progress_photos'], isTrue);
  });

  testWidgets('professor vê só os termos, sem finalidades de saúde',
      (tester) async {
    final (_, repository) = await _pump(tester, roles: {UserRole.coach});

    expect(find.byKey(const Key('consent_health_data')), findsNothing);
    expect(find.byKey(const Key('consent_progress_photos')), findsNothing);

    await _tap(tester, 'consent_terms');
    expect(_enabled(tester, _submit(l10n)), isTrue);
    await tester.tap(_submit(l10n));
    await tester.pumpAndSettle();

    expect(repository.puts.single, {'terms': true});
  });

  testWidgets('versão de termos velha mostra o erro traduzido', (tester) async {
    await _pump(
      tester,
      error:
          const ApiException(code: 'terms_version_mismatch', statusCode: 409),
    );

    await _tap(tester, 'consent_terms');
    await _tap(tester, 'consent_health_data');
    await tester.tap(_submit(l10n));
    await tester.pumpAndSettle();

    expect(find.text(l10n.errorTermsVersionMismatch), findsOneWidget);
  });
}
