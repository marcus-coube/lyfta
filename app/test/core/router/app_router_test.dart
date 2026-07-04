import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/auth/auth_controller.dart';
import 'package:lyfta/core/auth/auth_state.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/core/router/app_router.dart';

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
    final container = ProviderContainer();
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
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(authControllerProvider.notifier).signInStub({UserRole.coach});
    container.read(appRouterProvider).go('/home');
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    final l10n = lookupAppLocalizations(const Locale('pt'));
    expect(find.widgetWithText(AppBar, l10n.homeCoachTitle), findsOneWidget);
  });

  testWidgets('autenticado como student, /home cai no shell do aluno', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(authControllerProvider.notifier).signInStub({UserRole.student});
    container.read(appRouterProvider).go('/home');
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    final l10n = lookupAppLocalizations(const Locale('pt'));
    expect(find.widgetWithText(AppBar, l10n.homeStudentTitle), findsOneWidget);
  });

  testWidgets('autenticado tentando acessar /login volta para /home', (tester) async {
    final container = ProviderContainer();
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
