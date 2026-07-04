import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/design_system/design_system.dart';
import 'core/l10n/gen/app_localizations.dart';
import 'core/router/app_router.dart';

void main() {
  runApp(const ProviderScope(child: LyftaApp()));
}

class LyftaApp extends ConsumerWidget {
  const LyftaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

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
