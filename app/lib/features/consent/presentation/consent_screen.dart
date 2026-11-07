import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../account/data/account_repository.dart';
import 'consent_choices.dart';

/// Gate de consentimento (ADR-008 §1, P4.5): o usuário logado sem
/// consentimento vigente na versão atual dos termos — conta anterior ao P4.5
/// ou termo novo — cai aqui antes do app. O router (`/consent`) prende o
/// usuário nesta tela enquanto `AuthState.consentPending` valer.
class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key});

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  bool _terms = false;
  bool _healthData = false;
  bool _photos = false;
  bool _loading = false;
  String? _error;

  bool get _isStudent =>
      ref.read(authControllerProvider).roles.contains(UserRole.student);

  bool get _canSubmit => _terms && (!_isStudent || _healthData);

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await ref.read(accountRepositoryProvider).putConsents({
        ConsentPurpose.terms: true,
        if (_isStudent) ConsentPurpose.healthData: true,
        if (_isStudent) ConsentPurpose.progressPhotos: _photos,
      });
      // O router libera o app quando `consentPending` cair.
      await ref.read(authControllerProvider.notifier).applyConsentResult(
            accessToken: status.accessToken,
            needsConsent: status.needsConsent,
          );
    } catch (error) {
      if (mounted) setState(() => _error = describeApiError(context, error));
    } finally {
      if (mounted) setState(() => _loading = false);
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
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.consentTitle, style: LyType.display(c.textPrimary)),
                  const SizedBox(height: LySpace.x2),
                  Text(
                    l10n.consentSubtitle,
                    style: LyType.body(c.textSecondary),
                  ),
                  const SizedBox(height: LySpace.x6),
                  ConsentChoices(
                    showHealthData: _isStudent,
                    termsAccepted: _terms,
                    healthData: _healthData,
                    progressPhotos: _photos,
                    onTermsChanged: (v) => setState(() => _terms = v),
                    onHealthDataChanged: (v) => setState(() => _healthData = v),
                    onProgressPhotosChanged: (v) => setState(() => _photos = v),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: LySpace.x3),
                    Text(_error!, style: LyType.bodySm(c.danger)),
                  ],
                  const SizedBox(height: LySpace.x6),
                  LyButton(
                    label: l10n.consentSubmit,
                    loading: _loading,
                    onPressed: _canSubmit && !_loading ? _submit : null,
                  ),
                  const SizedBox(height: LySpace.x3),
                  Center(
                    child: TextButton(
                      onPressed: () =>
                          ref.read(authControllerProvider.notifier).signOut(),
                      child: Text(l10n.consentSignOut),
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
