import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';

/// Tela de recuperação de senha — ligada a
/// `POST /v1/auth/forgot-password` (P0.6). O backend sempre responde 200
/// (nunca vaza se o e-mail existe), então a UI sempre mostra a mensagem de
/// sucesso após o envio.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _loading = false;
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .forgotPassword(email: _emailController.text.trim());
    } catch (_) {
      // O backend não distingue erro/sucesso por design (não vaza contas);
      // mesmo uma falha de rede aqui não deve travar o usuário num loop —
      // mostramos a confirmação padrão de qualquer forma.
    } finally {
      if (mounted) setState(() { _loading = false; _sent = true; });
    }
  }

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
                    _sent ? l10n.forgotPasswordSuccess : l10n.forgotPasswordSubtitle,
                    style: LyType.body(c.textSecondary),
                  ),
                  const SizedBox(height: LySpace.x8),
                  if (!_sent) ...[
                    LyTextField(
                      label: l10n.loginEmailLabel,
                      hint: l10n.loginEmailHint,
                      prefixIcon: Icons.mail_outline,
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _loading ? null : _submit(),
                    ),
                    const SizedBox(height: LySpace.x6),
                    LyButton(
                      label: l10n.forgotPasswordSubmit,
                      loading: _loading,
                      onPressed: _loading ? null : _submit,
                    ),
                    const SizedBox(height: LySpace.x4),
                  ],
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
