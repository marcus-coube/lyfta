import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../account/data/account_repository.dart';
import '../../consent/presentation/consent_choices.dart';

/// Tela de aceite de convite — ligada a `POST /v1/invitations/accept`
/// (P0.6), com auto-login. O token chega via query param da rota `/invite`
/// (`APP_URL/#/invite?token=...`); no celular o link abre a versão web —
/// ver o comentário da rota em `app_router.dart`.
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
  bool _terms = false;
  bool _healthData = false;
  bool _photos = false;

  /// O aceite exige os termos e, para o aluno, os dados de saúde (ADR-008
  /// §1). O link do convite não revela o papel, então a tela pede as duas
  /// coisas a todo convidado; o servidor só grava as finalidades de saúde de
  /// quem é aluno.
  bool get _canSubmit => _terms && _healthData;

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
            consents: {
              ConsentPurpose.healthData: _healthData,
              ConsentPurpose.progressPhotos: _photos,
            },
          );
      // Sucesso: o auto-login já trocou a sessão. Quem já estava logado
      // continua em /invite (o redirect libera a rota com token), então a
      // ida ao shell é explícita.
      if (mounted) context.go('/home');
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
                  if (hasToken &&
                      ref.watch(authControllerProvider).status ==
                          AuthStatus.authenticated) ...[
                    const SizedBox(height: LySpace.x3),
                    Text(
                      l10n.inviteSwitchAccountNotice,
                      style: LyType.bodySm(c.warning),
                    ),
                  ],
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
                    ConsentChoices(
                      termsAccepted: _terms,
                      healthData: _healthData,
                      progressPhotos: _photos,
                      onTermsChanged: (v) => setState(() => _terms = v),
                      onHealthDataChanged: (v) => setState(() => _healthData = v),
                      onProgressPhotosChanged: (v) => setState(() => _photos = v),
                    ),
                    const SizedBox(height: LySpace.x6),
                    LyButton(
                      label: l10n.inviteSubmit,
                      loading: _loading,
                      onPressed: _loading || !_canSubmit ? null : _submit,
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
