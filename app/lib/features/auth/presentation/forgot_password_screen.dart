import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';

/// Tela de recuperação de senha — apenas visual por ora (P0.6 liga ao
/// endpoint `POST /v1/auth/forgot-password`).
class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(LySpace.x6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.forgotPasswordTitle, style: LyType.display(c.textPrimary)),
                  const SizedBox(height: LySpace.x2),
                  Text(
                    l10n.forgotPasswordSubtitle,
                    style: LyType.body(c.textSecondary),
                  ),
                  const SizedBox(height: LySpace.x8),
                  LyTextField(
                    label: l10n.loginEmailLabel,
                    hint: l10n.loginEmailHint,
                    prefixIcon: Icons.mail_outline,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: LySpace.x6),
                  LyButton(label: l10n.forgotPasswordSubmit, onPressed: () {}),
                  const SizedBox(height: LySpace.x4),
                  Center(
                    child: TextButton(
                      onPressed: () => context.go('/login'),
                      child: Text(
                        l10n.forgotPasswordBackToLogin,
                        style: LyType.bodySm(c.accent).copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
