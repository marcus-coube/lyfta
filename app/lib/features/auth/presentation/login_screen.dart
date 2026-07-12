import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../data/auth_repository.dart';
import '../data/auth_session.dart';

/// Tela de login — ligada ao `identity` (P0.6).
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
              child: Text(
                AppLocalizations.of(context).appVersion,
                style: LyType.caption(c.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginForm extends ConsumerStatefulWidget {
  const _LoginForm();

  @override
  ConsumerState<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends ConsumerState<_LoginForm> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit({String? tenantId}) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authControllerProvider.notifier).signIn(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            tenantId: tenantId,
          );
      // Sucesso: o redirect do go_router leva a /home ao ver
      // AuthStatus.authenticated — nada a fazer aqui.
    } on ApiException catch (e) {
      if (e.code == 'multiple_tenants') {
        if (!mounted) return;
        final chosen = await _showTenantPicker(context, e.tenantOptions);
        if (chosen != null) {
          await _submit(tenantId: chosen);
          return;
        }
      } else if (mounted) {
        setState(() => _errorMessage = e.message(l10n));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = const ApiException.network().message(l10n));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _showTenantPicker(
    BuildContext context,
    List<TenantOption> options,
  ) {
    final l10n = AppLocalizations.of(context);
    final c = context.ly;

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: LyRadius.lg.topLeft),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(LySpace.x6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.loginTenantSheetTitle, style: LyType.title(c.textPrimary)),
                const SizedBox(height: LySpace.x2),
                Text(l10n.loginTenantSheetSubtitle, style: LyType.body(c.textSecondary)),
                const SizedBox(height: LySpace.x5),
                for (final option in options)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(option.tenantName, style: LyType.body(c.textPrimary)),
                    trailing: Icon(Icons.chevron_right, color: c.textSecondary),
                    onTap: () => Navigator.of(sheetContext).pop(option.tenantId),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LyLogo(size: 44),
        const SizedBox(height: LySpace.x10),
        Text(l10n.loginWelcomeBack, style: LyType.display(c.textPrimary)),
        const SizedBox(height: LySpace.x2),
        Text(
          l10n.loginSubtitle,
          style: LyType.body(c.textSecondary),
        ),
        const SizedBox(height: LySpace.x8),
        LyTextField(
          label: l10n.loginEmailLabel,
          hint: l10n.loginEmailHint,
          prefixIcon: Icons.mail_outline,
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: LySpace.x5),
        LyTextField(
          label: l10n.loginPasswordLabel,
          hint: l10n.loginPasswordHint,
          prefixIcon: Icons.lock_outline,
          controller: _passwordController,
          obscure: true,
          textInputAction: TextInputAction.done,
          errorText: _errorMessage,
          onSubmitted: (_) => _loading ? null : _submit(),
        ),
        const SizedBox(height: LySpace.x3),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => context.go('/forgot'),
            child: Text(
              l10n.loginForgotPassword,
              style: LyType.bodySm(c.accent).copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: LySpace.x5),
        LyButton(
          label: l10n.loginSubmit,
          loading: _loading,
          onPressed: _loading ? null : () => _submit(),
        ),
        const SizedBox(height: LySpace.x6),
        Row(
          children: [
            Expanded(child: Divider(color: c.border)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: LySpace.x3),
              child: Text(l10n.loginOrDivider, style: LyType.caption(c.textSecondary)),
            ),
            Expanded(child: Divider(color: c.border)),
          ],
        ),
        const SizedBox(height: LySpace.x6),
        LyButton(
          label: l10n.loginContinueWithGoogle,
          variant: LyButtonVariant.secondary,
          icon: const Icon(Icons.g_mobiledata_rounded),
          onPressed: null,
        ),
        const SizedBox(height: LySpace.x8),
        Center(
          child: GestureDetector(
            onTap: () => context.go('/signup'),
            child: Text.rich(
              TextSpan(
                text: l10n.loginNewHerePrefix,
                style: LyType.bodySm(c.textSecondary),
                children: [
                  TextSpan(
                    text: l10n.loginNewHereSuffix,
                    style: LyType.bodySm(c.textPrimary).copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
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
