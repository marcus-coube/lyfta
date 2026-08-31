import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/auth_controller.dart';
import 'core/auth/auth_state.dart';
import 'core/design_system/design_system.dart';
import 'core/l10n/gen/app_localizations.dart';
import 'core/router/app_router.dart';
import 'features/workout/data/workout_repository.dart';

void main() {
  runApp(const ProviderScope(child: LyftaApp()));
}

class LyftaApp extends ConsumerWidget {
  const LyftaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    // Sair da conta apaga a execução guardada no aparelho. O banco local é
    // por aluno (ADR-003 §3), mas o celular pode ser emprestado — treino de
    // um não pode sobrar para o outro. Fica aqui, na raiz de composição,
    // porque `core/` não conhece feature (guideline flutter.md).
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      final signedOut = previous?.status == AuthStatus.authenticated &&
          next.status == AuthStatus.unauthenticated;
      if (signedOut) {
        unawaited(ref.read(workoutRepositoryProvider).clearLocal());
      }
    });

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: LyTheme.light(),
      darkTheme: LyTheme.dark(),
      // Dark é o tema de assinatura da marca; light fica disponível
      // para o contexto web/administrativo no futuro.
      themeMode: ThemeMode.dark,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    );
  }
}
