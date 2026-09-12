import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';

/// Tela de signup do professor/academia — cria o tenant + usuário owner
/// (`POST /v1/tenants`, ligado no P0.6).
class SignupScreen extends StatelessWidget {
  const SignupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;

            final form = ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: const _SignupForm(),
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
    );
  }
}

class _SignupForm extends ConsumerStatefulWidget {
  const _SignupForm();

  @override
  ConsumerState<_SignupForm> createState() => _SignupFormState();
}

class _SignupFormState extends ConsumerState<_SignupForm> {
  final _businessNameController = TextEditingController();
  final _slugController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _slugEditedManually = false;
  String? _errorMessage;
  String? _errorField;

  @override
  void dispose() {
    _businessNameController.dispose();
    _slugController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onBusinessNameChanged(String value) {
    if (_slugEditedManually) return;
    _slugController.text = _slugify(value);
  }

  String _slugify(String value) {
    final lower = value.toLowerCase().trim();
    final withDashes = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return withDashes.replaceAll(RegExp(r'^-+|-+$'), '');
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _loading = true;
      _errorMessage = null;
      _errorField = null;
    });

    try {
      await ref.read(authControllerProvider.notifier).signUpTenant(
            businessName: _businessNameController.text.trim(),
            slug: _slugController.text.trim(),
            name: _nameController.text.trim(),
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message(l10n);
        _errorField = e.code == 'validation_error' ? e.params['field']?.toString() : null;
      });
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LyLogo(size: 44),
        const SizedBox(height: LySpace.x8),
        Text(l10n.signupTitle, style: LyType.display(c.textPrimary)),
        const SizedBox(height: LySpace.x2),
        Text(l10n.signupSubtitle, style: LyType.body(c.textSecondary)),
        const SizedBox(height: LySpace.x8),
        LyTextField(
          label: l10n.signupBusinessNameLabel,
          hint: l10n.signupBusinessNameHint,
          prefixIcon: Icons.storefront_outlined,
          controller: _businessNameController,
          onChanged: _onBusinessNameChanged,
          textInputAction: TextInputAction.next,
          errorText: _errorField == 'business_name' ? _errorMessage : null,
        ),
        const SizedBox(height: LySpace.x5),
        LyTextField(
          label: l10n.signupSlugLabel,
          hint: l10n.signupSlugHint,
          prefixIcon: Icons.link,
          controller: _slugController,
          onChanged: (_) => _slugEditedManually = true,
          textInputAction: TextInputAction.next,
          errorText: _errorField == 'slug' ? _errorMessage : null,
        ),
        const SizedBox(height: LySpace.x5),
        LyTextField(
          label: l10n.signupNameLabel,
          hint: l10n.signupNameHint,
          prefixIcon: Icons.person_outline,
          controller: _nameController,
          textInputAction: TextInputAction.next,
          errorText: _errorField == 'name' ? _errorMessage : null,
        ),
        const SizedBox(height: LySpace.x5),
        LyTextField(
          label: l10n.loginEmailLabel,
          hint: l10n.loginEmailHint,
          prefixIcon: Icons.mail_outline,
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          errorText: _errorField == 'email' ? _errorMessage : null,
        ),
        const SizedBox(height: LySpace.x5),
        LyTextField(
          label: l10n.loginPasswordLabel,
          hint: l10n.loginPasswordHint,
          prefixIcon: Icons.lock_outline,
          controller: _passwordController,
          obscure: true,
          showPasswordLabel: l10n.commonShowPassword,
          hidePasswordLabel: l10n.commonHidePassword,
          textInputAction: TextInputAction.done,
          errorText: _errorField == 'password' ? _errorMessage : null,
          onSubmitted: (_) => _loading ? null : _submit(),
        ),
        if (_errorMessage != null && _errorField == null) ...[
          const SizedBox(height: LySpace.x3),
          Text(_errorMessage!, style: LyType.bodySm(c.danger)),
        ],
        const SizedBox(height: LySpace.x6),
        LyButton(
          label: l10n.signupSubmit,
          loading: _loading,
          onPressed: _loading ? null : _submit,
        ),
        const SizedBox(height: LySpace.x4),
        Center(
          child: TextButton(
            onPressed: () => context.go('/login'),
            child: Text(
              l10n.signupBackToLogin,
              style: LyType.bodySm(c.accent).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}
