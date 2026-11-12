import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';

/// Tela de espera enquanto a sessão guardada é revalidada no identity
/// (`AuthStatus.unknown`). Antes o router mandava esse intervalo para
/// `/login`, e quem já estava logado via o formulário por alguns segundos —
/// convite a digitar a senha à toa (achado A10 do E2E 2.0).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LyLogo(size: 44),
            SizedBox(height: LySpace.x6),
            SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ],
        ),
      ),
    );
  }
}
