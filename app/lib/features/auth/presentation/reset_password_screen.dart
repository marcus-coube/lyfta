import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';

/// Tela de redefinição de senha — consome o token de
/// `POST /v1/auth/reset-password` (P0.6). Chega via link do e-mail
/// (`APP_URL/#/reset?token=...`, mesmo padrão do convite).
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.token});

  final String? token;

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _success = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final token = widget.token;
    if (token == null) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authControllerProvider.notifier).resetPassword(
            token: token,
            password: _passwordController.text,
          );
      if (mounted) setState(() => _success = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message(l10n));
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = const ApiException.network().message(l10n));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final hasToken = widget.token != null && widget.token!.isNotEmpty;

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
                  Text(l10n.resetPasswordTitle, style: LyType.display(c.textPrimary)),
                  const SizedBox(height: LySpace.x2),
                  if (!hasToken)
                    Text(l10n.resetPasswordInvalidLink, style: LyType.body(c.danger))
                  else if (_success)
                    Text(l10n.resetPasswordSuccess, style: LyType.body(c.textSecondary))
                  else
                    Text(l10n.resetPasswordSubtitle, style: LyType.body(c.textSecondary)),
                  const SizedBox(height: LySpace.x8),
                  if (hasToken && !_success) ...[
                    LyTextField(
                      label: l10n.resetPasswordNewLabel,
                      hint: l10n.loginPasswordHint,
                      prefixIcon: Icons.lock_outline,
                      controller: _passwordController,
                      obscure: true,
                      showPasswordLabel: l10n.commonShowPassword,
                      hidePasswordLabel: l10n.commonHidePassword,
                      textInputAction: TextInputAction.done,
                      errorText: _errorMessage,
                      onSubmitted: (_) => _loading ? null : _submit(),
                    ),
                    const SizedBox(height: LySpace.x6),
                    LyButton(
                      label: l10n.resetPasswordSubmit,
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
