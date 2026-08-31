import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/auth/auth_controller.dart';
import 'package:lyfta/core/auth/auth_state.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/core/router/app_router.dart';
import 'package:lyfta/features/students/presentation/students_controller.dart';
import 'package:lyfta/features/workout/data/sync_worker.dart';
import 'package:lyfta/features/workout/data/workout_repository.dart';
import 'package:lyfta/features/workout/domain/today.dart';
import 'package:lyfta/features/workout/presentation/session_controller.dart';
import 'package:lyfta/features/workout/presentation/today_controller.dart';

/// A aba inicial do professor é a lista de alunos (P1.6), que bate em dois
/// serviços. Este teste é de **roteamento**: a lista entra vazia e sem rede,
/// senão o `pumpAndSettle` esperaria para sempre por uma requisição que
/// nunca responde no ambiente de teste.
class _EmptyStudents extends StudentsController {
  @override
  Future<List<StudentRow>> build() async => [];
}

/// Mesma ideia do lado do aluno (P1.7): a tela Hoje lê banco local e rede,
/// e nenhum dos dois existe num teste de roteamento.
class _NoPlanToday extends TodayController {
  @override
  Future<TodayView> build() async => TodayView(
        today: const Today(
          status: TodayStatus.noPlan,
          previousLoads: {},
          recentSessions: [],
        ),
        fetchedAt: DateTime.utc(2026, 8, 31),
      );
}

class _NoSession extends SessionController {
  @override
  Future<SessionState?> build() async => null;
}

class _IdleSync extends SyncWorker {
  @override
  SyncState build() => const SyncState();
}

ProviderContainer _container() {
  return ProviderContainer(
    overrides: [
      studentsProvider.overrideWith(_EmptyStudents.new),
      todayControllerProvider.overrideWith(_NoPlanToday.new),
      sessionControllerProvider.overrideWith(_NoSession.new),
      syncWorkerProvider.overrideWith(_IdleSync.new),
    ],
  );
}

Widget _app(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: LyTheme.dark(),
      locale: const Locale('pt'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: container.read(appRouterProvider),
    ),
  );
}

void main() {
  testWidgets('sem sessão, rota protegida redireciona para /login', (tester) async {
    final container = _container();
    addTearDown(container.dispose);

    container.read(appRouterProvider).go('/home');
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    expect(find.byType(TextButton), findsWidgets);
    final location =
        container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.toString();
    expect(location, '/login');
  });

  testWidgets('autenticado como coach, /home cai no shell do professor', (tester) async {
    final container = _container();
    addTearDown(container.dispose);

    container.read(authControllerProvider.notifier).signInStub({UserRole.coach});
    container.read(appRouterProvider).go('/home');
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    final l10n = lookupAppLocalizations(const Locale('pt'));
    expect(find.widgetWithText(AppBar, l10n.homeCoachTabStudents), findsOneWidget);
  });

  testWidgets('autenticado como student, /home cai no shell do aluno', (tester) async {
    final container = _container();
    addTearDown(container.dispose);

    container.read(authControllerProvider.notifier).signInStub({UserRole.student});
    container.read(appRouterProvider).go('/home');
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    final l10n = lookupAppLocalizations(const Locale('pt'));
    expect(find.widgetWithText(AppBar, l10n.homeStudentTabToday), findsOneWidget);
  });

  testWidgets('autenticado tentando acessar /login volta para /home', (tester) async {
    final container = _container();
    addTearDown(container.dispose);

    container.read(authControllerProvider.notifier).signInStub({UserRole.student});
    container.read(appRouterProvider).go('/login');
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    final location =
        container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.toString();
    expect(location, '/home');
  });
}
