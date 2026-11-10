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
import 'package:lyfta/features/account/data/tenant_repository.dart';
import 'package:lyfta/features/account/presentation/account_screen.dart';

class _OwnerAuth extends AuthController {
  _OwnerAuth({this.owner = true});

  final bool owner;

  @override
  AuthState build() => AuthState.authenticated(
        roles: {UserRole.coach},
        tenantId: 'tenant-1',
        userId: 'user-1',
        isOwner: owner,
      );
}

class _FakeTenantRepository extends TenantRepository {
  _FakeTenantRepository({this.updateError}) : super(Dio());

  final ApiException? updateError;
  var current = const TenantSettings(
    id: 'tenant-1',
    name: 'Academia Teste',
    slug: 'academia-teste',
    locale: 'pt-BR',
    timezone: 'America/Sao_Paulo',
    coachBillingAccess: 'status_only',
  );
  final updates = <({String? name, String? timezone, String? access})>[];

  @override
  Future<TenantSettings> get() async => current;

  @override
  Future<TenantSettings> update({
    String? name,
    String? timezone,
    String? coachBillingAccess,
  }) async {
    updates.add(
      (name: name, timezone: timezone, access: coachBillingAccess),
    );
    if (updateError != null) throw updateError!;
    current = TenantSettings(
      id: current.id,
      name: name ?? current.name,
      slug: current.slug,
      locale: current.locale,
      timezone: timezone ?? current.timezone,
      coachBillingAccess: coachBillingAccess ?? current.coachBillingAccess,
    );
    return current;
  }
}

class _FakeAccountRepository extends AccountRepository {
  _FakeAccountRepository() : super(Dio(), termsVersion: 'v-teste');
}

Future<_FakeTenantRepository> _pump(
  WidgetTester tester, {
  bool owner = true,
  ApiException? updateError,
}) async {
  final tenants = _FakeTenantRepository(updateError: updateError);
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _OwnerAuth(owner: owner)),
        accountRepositoryProvider.overrideWithValue(_FakeAccountRepository()),
        tenantRepositoryProvider.overrideWithValue(tenants),
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
  return tenants;
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('pt'));

  testWidgets('owner vê nome e fuso atuais e troca o fuso pela lista',
      (tester) async {
    final tenants = await _pump(tester);

    expect(find.text(l10n.organizationSection), findsOneWidget);
    expect(find.text('Academia Teste'), findsOneWidget);
    expect(find.textContaining('America/Sao_Paulo'), findsOneWidget);

    await tester.tap(find.byKey(const Key('organization_timezone')));
    await tester.pumpAndSettle();
    // Busca filtra a lista.
    await tester.enterText(find.byKey(const Key('timezone_search')), 'lisb');
    await tester.pump();
    expect(find.byKey(const Key('timezone_America/Manaus')), findsNothing);
    await tester.tap(find.byKey(const Key('timezone_Europe/Lisbon')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('organization_save')));
    await tester.pumpAndSettle();

    expect(tenants.updates.single.timezone, 'Europe/Lisbon');
    expect(find.text(l10n.organizationSaved), findsOneWidget);
    expect(find.textContaining('Europe/Lisbon'), findsOneWidget);
  });

  testWidgets(
      'toggle do financeiro explica cada modo e salva na hora (ADR-017 §3)',
      (tester) async {
    final tenants = await _pump(tester);

    expect(find.text(l10n.organizationCoachBillingTitle), findsOneWidget);
    expect(find.text(l10n.organizationCoachBillingOff), findsOneWidget);

    await tester.tap(find.byKey(const Key('organization_coach_billing')));
    await tester.pumpAndSettle();

    expect(tenants.updates.single.access, 'own_students');
    expect(tenants.updates.single.name, isNull);
    expect(find.text(l10n.organizationCoachBillingOn), findsOneWidget);
    expect(find.text(l10n.organizationCoachBillingSaved), findsOneWidget);

    await tester.tap(find.byKey(const Key('organization_coach_billing')));
    await tester.pumpAndSettle();
    expect(tenants.updates.last.access, 'status_only');
  });

  testWidgets('fuso digitado em "Outro" inválido mostra o erro do servidor',
      (tester) async {
    final tenants = await _pump(
      tester,
      updateError:
          const ApiException(code: 'invalid_timezone', statusCode: 422),
    );

    await tester.tap(find.byKey(const Key('organization_timezone')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timezone_other')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('timezone_custom')),
      'Marte/Olympus',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('timezone_custom_confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('organization_save')));
    await tester.pumpAndSettle();

    expect(tenants.updates.single.timezone, 'Marte/Olympus');
    expect(find.text(l10n.errorInvalidTimezone), findsOneWidget);
  });

  testWidgets('quem não é owner não vê a seção', (tester) async {
    await _pump(tester, owner: false);
    expect(find.text(l10n.organizationSection), findsNothing);
    expect(find.byKey(const Key('organization_save')), findsNothing);
  });
}
