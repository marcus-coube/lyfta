import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/ly_date_field.dart';
import '../data/account_repository.dart';
import 'account_controller.dart';

/// Seção "Meus dados" da tela Conta do aluno (P5.4): telefone e nascimento.
/// O nome só o professor muda (P5.2).
class ProfileSection extends ConsumerStatefulWidget {
  const ProfileSection({super.key});

  @override
  ConsumerState<ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends ConsumerState<ProfileSection> {
  final _phone = TextEditingController();
  DateTime? _birth;
  MyProfile? _saved;
  bool _saving = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  /// Preenche uma vez por versão salva: não sobrescreve o que o aluno digita.
  void _hydrate(MyProfile profile) {
    if (identical(_saved, profile)) return;
    _saved = profile;
    _phone.text = profile.phone ?? '';
    _birth = profile.birthDate;
  }

  bool get _dirty =>
      _saved != null &&
      (_phone.text.trim() != (_saved!.phone ?? '') ||
          _birth != _saved!.birthDate);

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final updated = await ref.read(accountRepositoryProvider).updateProfile(
            phone: _phone.text.trim(),
            birthDate:
                _birth == null ? '' : DateFormat('yyyy-MM-dd').format(_birth!),
          );
      if (!mounted) return;
      setState(() => _hydrate(updated));
      messenger.showSnackBar(SnackBar(content: Text(l10n.accountProfileSaved)));
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(describeApiError(context, error))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(myProfileProvider);
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: LySpace.x2),
          child: Text(
            l10n.accountProfileSection,
            style: LyType.label(c.textSecondary),
          ),
        ),
        profile.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(LySpace.x4),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => ListTile(
            key: const Key('profile_error'),
            leading: Icon(Icons.error_outline, color: c.danger),
            title: Text(describeApiError(context, error)),
            trailing: TextButton(
              onPressed: () => ref.invalidate(myProfileProvider),
              child: Text(l10n.commonRetry),
            ),
          ),
          data: (data) {
            _hydrate(data);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LyTextField(
                  key: const Key('profile_phone'),
                  label: l10n.profilePhoneLabel,
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: LySpace.x3),
                LyDateField(
                  label: l10n.profileBirthLabel,
                  value: _birth,
                  emptyLabel: l10n.profileBirthEmpty,
                  clearLabel: l10n.profileBirthClear,
                  firstDate: DateTime(1900),
                  lastDate: DateTime(now.year, now.month, now.day),
                  onChanged: (value) => setState(() => _birth = value),
                ),
                const SizedBox(height: LySpace.x3),
                LyButton(
                  key: const Key('profile_save'),
                  label: l10n.commonSave,
                  expanded: false,
                  loading: _saving,
                  onPressed: _dirty && !_saving ? _save : null,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
