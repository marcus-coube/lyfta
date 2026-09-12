import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';

/// Tela de aceite de convite — ligada a `POST /v1/invitations/accept`
/// (P0.6), com auto-login. O token chega via query param da rota `/invite`
/// tanto em web (`APP_URL/#/invite?token=...`) quanto por deep link
/// `lyfta://invite?token=...` no mobile (esquema registrado nas plataformas
/// nativas geradas por `flutter create .`, fora do que este repo versiona —
/// ver app/README.md).
class InviteAcceptScreen extends ConsumerStatefulWidget {
  const InviteAcceptScreen({super.key, this.token});

  final String? token;

  @override
  ConsumerState<InviteAcceptScreen> createState() => _InviteAcceptScreenState();
}

class _InviteAcceptScreenState extends ConsumerState<InviteAcceptScreen> {
  final _passwordController = TextEditingController();
  bool _loading = false;
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
      await ref.read(authControllerProvider.notifier).acceptInvite(
            token: token,
            password: _passwordController.text,
          );
      // Sucesso: auto-login já atualizou AuthState; o redirect do go_router
      // leva ao shell certo — nada a fazer aqui.
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
                  Text(l10n.inviteTitle, style: LyType.display(c.textPrimary)),
                  const SizedBox(height: LySpace.x2),
                  Text(
                    hasToken ? l10n.inviteSubtitle : l10n.inviteInvalidLink,
                    style: LyType.body(hasToken ? c.textSecondary : c.danger),
                  ),
                  const SizedBox(height: LySpace.x8),
                  if (hasToken) ...[
                    LyTextField(
                      label: l10n.inviteNewPasswordLabel,
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
                      label: l10n.inviteSubmit,
                      loading: _loading,
                      onPressed: _loading ? null : _submit,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
