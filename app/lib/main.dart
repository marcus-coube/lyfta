import 'package:flutter/material.dart';

import 'core/design_system/design_system.dart';
import 'features/auth/presentation/login_screen.dart';

void main() {
  runApp(const LyftaApp());
}

class LyftaApp extends StatelessWidget {
  const LyftaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lyfta',
      debugShowCheckedModeBanner: false,
      theme: LyTheme.light(),
      darkTheme: LyTheme.dark(),
      // Dark é o tema de assinatura da marca; light fica disponível
      // para o contexto web/administrativo no futuro.
      themeMode: ThemeMode.dark,
      home: const LoginScreen(),
    );
  }
}
