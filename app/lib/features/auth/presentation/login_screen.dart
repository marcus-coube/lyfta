import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';

/// Tela de login — apenas visual (sem autenticação real).
///
/// Mobile: formulário em tela cheia. Desktop/web (>= 900px): card
/// centralizado sobre o fundo com glow da marca.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ly;

    return Scaffold(
      body: Stack(
        children: [
          const _BrandGlowBackground(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 900;

                final form = ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: const _LoginForm(),
                );

                if (!isWide) {
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(LySpace.x6),
                      child: form,
                    ),
                  );
                }

                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(LySpace.x8),
                    child: LyCard(
                      elevated: true,
                      padding: const EdgeInsets.all(LySpace.x10),
                      child: form,
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: LySpace.x4,
            child: Center(
              child: Text('v0.1.0', style: LyType.caption(c.textSecondary)),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm();

  @override
  Widget build(BuildContext context) {
    final c = context.ly;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LyLogo(size: 44),
        const SizedBox(height: LySpace.x10),
        Text('Bem-vindo de volta', style: LyType.display(c.textPrimary)),
        const SizedBox(height: LySpace.x2),
        Text(
          'Entre para acompanhar seus treinos e sua evolução.',
          style: LyType.body(c.textSecondary),
        ),
        const SizedBox(height: LySpace.x8),
        const LyTextField(
          label: 'E-mail',
          hint: 'voce@exemplo.com',
          prefixIcon: Icons.mail_outline,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: LySpace.x5),
        const LyTextField(
          label: 'Senha',
          hint: '••••••••',
          prefixIcon: Icons.lock_outline,
          obscure: true,
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: LySpace.x3),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {},
            child: Text(
              'Esqueci minha senha',
              style: LyType.bodySm(c.accent).copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: LySpace.x5),
        LyButton(label: 'Entrar', onPressed: () {}),
        const SizedBox(height: LySpace.x6),
        Row(
          children: [
            Expanded(child: Divider(color: c.border)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: LySpace.x3),
              child: Text('ou', style: LyType.caption(c.textSecondary)),
            ),
            Expanded(child: Divider(color: c.border)),
          ],
        ),
        const SizedBox(height: LySpace.x6),
        LyButton(
          label: 'Continuar com Google',
          variant: LyButtonVariant.secondary,
          icon: const Icon(Icons.g_mobiledata_rounded),
          onPressed: () {},
        ),
        const SizedBox(height: LySpace.x8),
        Center(
          child: Text.rich(
            TextSpan(
              text: 'Novo por aqui? ',
              style: LyType.bodySm(c.textSecondary),
              children: [
                TextSpan(
                  text: 'Seu coach ou academia envia o convite.',
                  style: LyType.bodySm(c.textPrimary).copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

/// Fundo grafite com glows sutis da marca — identidade "energia na
/// penumbra da academia".
class _BrandGlowBackground extends StatelessWidget {
  const _BrandGlowBackground();

  @override
  Widget build(BuildContext context) {
    final c = context.ly;

    return DecoratedBox(
      decoration: BoxDecoration(color: c.background),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -80,
            child: _glow(LyPalette.lime.withValues(alpha: 0.14), 420),
          ),
          Positioned(
            bottom: -160,
            left: -120,
            child: _glow(LyPalette.lime.withValues(alpha: 0.06), 520),
          ),
        ],
      ),
    );
  }

  Widget _glow(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
