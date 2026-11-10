import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/auth/auth_controller.dart';
import 'package:lyfta/core/auth/auth_state.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/account/data/tenant_repository.dart';
import 'package:lyfta/features/billing/data/billing_repository.dart';
import 'package:lyfta/features/chat/presentation/conversations_controller.dart';
import 'package:lyfta/features/coach_shell/presentation/coach_shell_screen.dart';
import 'package:lyfta/features/students/data/student_overview_repository.dart';
import 'package:lyfta/features/students/data/student_repository.dart';
import 'package:lyfta/features/students/domain/student.dart';
import 'package:lyfta/features/students/presentation/students_controller.dart';

import '../billing/billing_fakes.dart';

class _Auth extends AuthController {
  _Auth({required this.isOwner});

  final bool isOwner;

  @override
  AuthState build() => AuthState.authenticated(
        roles: {UserRole.coach},
        tenantId: 't',
        userId: 'u',
        isOwner: isOwner,
      );
}

class _Tenants extends TenantRepository {
  _Tenants(this.access) : super(Dio());

  final String access;

  @override
  Future<TenantSettings> get() async => TenantSettings(
        id: 't',
        name: 'Org',
        slug: 'org',
        locale: 'pt-BR',
        timezone: 'America/Sao_Paulo',
        coachBillingAccess: access,
      );
}

class _Students extends StudentRepository {
  _Students() : super(Dio());

  @override
  Future<StudentPage> list({
    String query = '',
    StudentStatusFilter status = StudentStatusFilter.active,
    String? coachId,
    String? cursor,
    int? limit,
  }) async =>
      const StudentPage(items: []);
}

class _Overview extends StudentOverviewRepository {
  _Overview() : super(Dio());
}

final l10n = lookupAppLocalizations(const Locale('pt'));

Future<void> _pump(
  WidgetTester tester, {
  required bool isOwner,
  String access = 'status_only',
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _Auth(isOwner: isOwner)),
        tenantRepositoryProvider.overrideWithValue(_Tenants(access)),
        billingRepositoryProvider.overrideWithValue(FakeBillingRepository()),
        studentRepositoryProvider.overrideWithValue(_Students()),
        studentOverviewRepositoryProvider.overrideWithValue(_Overview()),
        unreadTotalProvider.overrideWithValue(0),
      ],
      child: MaterialApp(
        theme: LyTheme.dark(),
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const CoachShellScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('owner tem a aba Financeiro', (tester) async {
    await _pump(tester, isOwner: true);

    expect(find.text(l10n.homeCoachTabBilling), findsOneWidget);
    await tester.tap(find.text(l10n.homeCoachTabBilling));
    await tester.pumpAndSettle();
    // Dentro dela: faturas e planos (só owner).
    expect(find.text(l10n.billingTabPlans), findsOneWidget);
  });

  testWidgets('coach com o acesso desligado não vê a aba', (tester) async {
    await _pump(tester, isOwner: false);

    expect(find.text(l10n.homeCoachTabStudents), findsWidgets);
    expect(find.text(l10n.homeCoachTabBilling), findsNothing);
  });

  testWidgets('coach com own_students vê a aba, sem planos', (tester) async {
    await _pump(tester, isOwner: false, access: 'own_students');

    expect(find.text(l10n.homeCoachTabBilling), findsOneWidget);
    await tester.tap(find.text(l10n.homeCoachTabBilling));
    await tester.pumpAndSettle();
    expect(find.text(l10n.billingTabPlans), findsNothing);
    expect(find.text(l10n.invoicesEmpty), findsOneWidget);
  });
}
