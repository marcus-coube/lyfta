import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/auth_controller.dart';
import 'core/auth/auth_state.dart';
import 'core/design_system/design_system.dart';
import 'core/l10n/gen/app_localizations.dart';
import 'core/push/push_provider.dart';
import 'core/router/app_router.dart';
import 'features/workout/data/workout_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: LyftaApp()));
  // Push (P3.4/P3.5 §4): só mobile — web fica com o badge in-app da aba Chat
  // no MVP (ADR-012 §2, web push é 3.0). Adiado para depois do primeiro
  // frame (P4.2 §1, "app leve"): `Firebase.initializeApp()` faz I/O nativo
  // e, com `await` antes de `runApp`, atrasava a pintura da tela de login
  // em todo boot mobile — inclusive nos devices sem `google-services.json`
  // versionado (bloqueio conhecido, ver app/README.md § Firebase), onde a
  // chamada nem chega a valer a pena. `PushService.init`/`ensureRegistered`
  // (`core/push/push_service.dart`) já toleram Firebase ainda não pronto —
  // cada chamada ao SDK está em try/catch — então adiar aqui não muda o
  // comportamento em caso de falha, só quando ele começa.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_initFirebase());
  });
}

Future<void> _initFirebase() async {
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    try {
      await Firebase.initializeApp();
    } catch (_) {
      // Conforto, não requisito — ver comentário acima.
    }
  }
}

class LyftaApp extends ConsumerWidget {
  const LyftaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    // Só ler o provider já basta para ligar tudo (registro do token no
    // sign-in, deep link da notificação tocada) — ele se autogerencia via
    // `ref.listen` interno, mesmo padrão do `commsSocketProvider`.
    ref.watch(pushServiceProvider);

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
