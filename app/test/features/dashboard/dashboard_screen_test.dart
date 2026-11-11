import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/auth/auth_controller.dart';
import 'package:lyfta/core/auth/auth_state.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/chat/data/participant_directory.dart';
import 'package:lyfta/features/dashboard/data/dashboard_repository.dart';
import 'package:lyfta/features/dashboard/presentation/dashboard_screen.dart';

import 'dashboard_fakes.dart';

final l10n = lookupAppLocalizations(const Locale('pt'));

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

class _Directory extends ParticipantDirectoryRepository {
  _Directory() : super(Dio());

  @override
  Future<Map<String, String>> names(Iterable<String> ids) async => {
        's-trained': 'Ana Alves',
        's-going': 'Bruno Costa',
        's-stalled': 'Carla Dias',
        's-new': 'Davi Nunes',
        's-noplan': 'Elisa Reis',
      };
}

Future<void> _pump(
  WidgetTester tester,
  FakeDashboardRepository fake, {
  bool isOwner = true,
  Size size = const Size(1200, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _Auth(isOwner: isOwner)),
        dashboardRepositoryProvider.overrideWithValue(fake),
        participantDirectoryRepositoryProvider.overrideWithValue(_Directory()),
      ],
      child: MaterialApp(
        theme: LyTheme.dark(),
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: DashboardScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('owner vê os cards do seed, com valores e gráfico',
      (tester) async {
    await _pump(tester, FakeDashboardRepository());

    // Alunos e check-ins.
    expect(find.text('12'), findsOneWidget);
    expect(find.text(l10n.dashboardStudentsNew(4)), findsOneWidget);
    expect(find.text(l10n.dashboardStudentsPending(2)), findsOneWidget);
    expect(find.text('5'), findsOneWidget);

    // Hoje: nomes cruzados pelo diretório; sem plano só como contagem.
    expect(find.text('Ana Alves'), findsOneWidget);
    expect(find.text('Bruno Costa'), findsOneWidget);
    expect(find.text(l10n.dashboardTodayNoPlan(1)), findsOneWidget);
    expect(find.text('Elisa Reis'), findsNothing);

    // Sem treinar: só quem já treinou (a Carla), não o aluno novo.
    expect(find.text(l10n.studentsLastWorkoutDaysAgo(9)), findsOneWidget);
    expect(find.text('Carla Dias'), findsNWidgets(2)); // hoje + parado
    expect(find.text('Davi Nunes'), findsOneWidget); // só em hoje

    // Financeiro.
    expect(find.byKey(const Key('dashboard_card_billing')), findsOneWidget);
    expect(find.textContaining('1.500,00'), findsOneWidget);
    expect(find.textContaining('900,00'), findsOneWidget);
    expect(find.textContaining('300,00'), findsOneWidget);
    expect(find.byKey(const Key('dashboard_card_series')), findsOneWidget);
  });

  testWidgets('coach não vê cards de valor e nem chama o billing',
      (tester) async {
    final fake = FakeDashboardRepository();
    await _pump(tester, fake, isOwner: false);

    expect(find.byKey(const Key('dashboard_card_students')), findsOneWidget);
    expect(find.byKey(const Key('dashboard_card_billing')), findsNothing);
    expect(find.byKey(const Key('dashboard_card_series')), findsNothing);
    expect(find.text(l10n.dashboardCardReceived), findsNothing);
    expect(fake.billingCalls, 0);
  });

  testWidgets('card com serviço fora mostra retry sem afetar os outros',
      (tester) async {
    final fake = FakeDashboardRepository()..todayDown = true;
    await _pump(tester, fake);

    // Hoje e Sem treinar dependem do workout: os dois mostram retry.
    expect(find.text(l10n.commonRetry), findsNWidgets(2));
    // Os demais seguem de pé.
    expect(find.text('12'), findsOneWidget);
    expect(find.textContaining('1.500,00'), findsOneWidget);

    fake.todayDown = false;
    await tester.tap(find.text(l10n.commonRetry).first);
    await tester.pumpAndSettle();

    expect(find.text(l10n.commonRetry), findsNothing);
    expect(find.text('Ana Alves'), findsOneWidget);
  });

  testWidgets('billing fora não derruba o resto e retry recarrega',
      (tester) async {
    final fake = FakeDashboardRepository()..billingDown = true;
    await _pump(tester, fake);

    expect(find.text(l10n.commonRetry), findsNWidgets(2));
    expect(find.text('Ana Alves'), findsOneWidget);

    fake.billingDown = false;
    await tester.tap(find.text(l10n.commonRetry).first);
    await tester.pumpAndSettle();
    expect(find.text(l10n.commonRetry), findsNothing);
    expect(find.textContaining('1.500,00'), findsOneWidget);
  });

  testWidgets('celular: uma coluna, sem overflow', (tester) async {
    await _pump(
      tester,
      FakeDashboardRepository(),
      size: const Size(390, 1800),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('dashboard_card_today')), findsOneWidget);
  });
}
