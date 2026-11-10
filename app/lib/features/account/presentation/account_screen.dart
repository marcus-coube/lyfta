import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/legal/legal_document.dart';
import '../data/account_repository.dart';
import 'account_controller.dart';
import 'organization_section.dart';
import 'profile_section.dart';

/// Tela Conta (P4.5): privacidade (fotos de evolução, só aluno), documentos
/// legais, sair e "Excluir minha conta" (ADR-008 §2). É o único lugar do app
/// com logout e com a revogação de consentimento.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _savingConsent = false;

  Future<void> _togglePhotos(bool granted) async {
    setState(() => _savingConsent = true);
    try {
      await setConsent(ref, ConsentPurpose.progressPhotos, granted: granted);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(describeApiError(context, error))),
        );
      }
    } finally {
      if (mounted) setState(() => _savingConsent = false);
    }
  }

  Future<void> _confirmDelete() async {
    // Sucesso: `completeAccountDeletion` já derrubou a sessão e o router leva
    // ao login — nada a fazer aqui depois do diálogo.
    await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final auth = ref.watch(authControllerProvider);
    final isStudent = auth.roles.contains(UserRole.student);
    final status = ref.watch(consentStatusProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountTitle)),
      body: ListView(
        padding: const EdgeInsets.all(LySpace.x4),
        children: [
          // Organização (P5.1): só o owner mexe no nome e no fuso do tenant.
          if (auth.isOwner) ...[
            const OrganizationSection(),
            const SizedBox(height: LySpace.x4),
          ],
          if (isStudent) ...[
            const ProfileSection(),
            const SizedBox(height: LySpace.x4),
            _Section(l10n.accountPrivacySection),
            SwitchListTile(
              key: const Key('account_photos_switch'),
              value: status.valueOrNull?.has(ConsentPurpose.progressPhotos) ??
                  false,
              onChanged:
                  status.hasValue && !_savingConsent ? _togglePhotos : null,
              title: Text(l10n.accountPhotosTitle),
              subtitle: Text(l10n.accountPhotosSubtitle),
            ),
            const SizedBox(height: LySpace.x4),
          ],
          _Section(l10n.accountLegalSection),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(l10n.consentReadTerms),
            onTap: () => showLegalDocument(context, LegalDocument.terms),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(l10n.consentReadPrivacy),
            onTap: () => showLegalDocument(context, LegalDocument.privacy),
          ),
          const SizedBox(height: LySpace.x4),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(l10n.accountSignOut),
            onTap: () async {
              await ref.read(authControllerProvider.notifier).signOut();
            },
          ),
          const SizedBox(height: LySpace.x4),
          _Section(l10n.accountDeleteSection),
          ListTile(
            key: const Key('account_delete'),
            leading: Icon(Icons.delete_forever_outlined, color: c.danger),
            title: Text(
              l10n.accountDeleteTitle,
              style: TextStyle(color: c.danger),
            ),
            subtitle: Text(l10n.accountDeleteSubtitle),
            onTap: _confirmDelete,
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    return Padding(
      padding: const EdgeInsets.only(bottom: LySpace.x2),
      child: Text(label, style: LyType.label(c.textSecondary)),
    );
  }
}

/// Aviso do que é apagado + confirmação por senha. Fecha com `true` quando a
/// exclusão concluiu.
class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await deleteAccount(ref, _password.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = describeApiError(context, error);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.accountDeleteDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.accountDeleteDialogBody),
            const SizedBox(height: LySpace.x4),
            TextField(
              key: const Key('delete_password'),
              controller: _password,
              obscureText: true,
              enabled: !_loading,
              decoration:
                  InputDecoration(labelText: l10n.accountDeletePasswordLabel),
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) ...[
              const SizedBox(height: LySpace.x2),
              Text(_error!, style: LyType.bodySm(c.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          key: const Key('delete_confirm'),
          onPressed: _loading || _password.text.isEmpty ? null : _delete,
          child: Text(
            l10n.accountDeleteConfirm,
            style: TextStyle(color: c.danger),
          ),
        ),
      ],
    );
  }
}
