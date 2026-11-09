import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../data/tenant_repository.dart';

/// Fusos mais comuns do Brasil e de Portugal (nomes IANA são dado, não
/// texto de UI). Qualquer outro nome IANA entra por "Outro fuso…".
const commonTimezones = <String>[
  'America/Sao_Paulo',
  'America/Manaus',
  'America/Belem',
  'America/Fortaleza',
  'America/Recife',
  'America/Bahia',
  'America/Cuiaba',
  'America/Campo_Grande',
  'America/Porto_Velho',
  'America/Rio_Branco',
  'America/Noronha',
  'Europe/Lisbon',
  'Atlantic/Madeira',
  'Atlantic/Azores',
];

/// Seção "Organização" da tela Conta do owner (P5.1): nome e fuso do tenant.
/// O toggle de acesso do coach ao financeiro entra na P7.4.
class OrganizationSection extends ConsumerStatefulWidget {
  const OrganizationSection({super.key});

  @override
  ConsumerState<OrganizationSection> createState() =>
      _OrganizationSectionState();
}

class _OrganizationSectionState extends ConsumerState<OrganizationSection> {
  final _name = TextEditingController();
  String? _timezone;
  String? _loadedFor;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _hydrate(TenantSettings tenant) {
    // Só preenche uma vez por versão carregada: não sobrescreve o que o owner
    // já está digitando.
    final key = '${tenant.name}|${tenant.timezone}';
    if (_loadedFor == key) return;
    _loadedFor = key;
    _name.text = tenant.name;
    _timezone = tenant.timezone;
  }

  Future<void> _pickTimezone() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _TimezoneDialog(current: _timezone),
    );
    if (picked != null && mounted) setState(() => _timezone = picked);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final updated = await ref.read(tenantRepositoryProvider).update(
            name: _name.text.trim(),
            timezone: _timezone,
          );
      _loadedFor = null;
      ref.invalidate(tenantSettingsProvider);
      messenger.showSnackBar(SnackBar(content: Text(l10n.organizationSaved)));
      if (mounted) {
        setState(() {
          _name.text = updated.name;
          _timezone = updated.timezone;
        });
      }
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
    final tenant = ref.watch(tenantSettingsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: LySpace.x2),
          child: Text(
            l10n.organizationSection,
            style: LyType.label(c.textSecondary),
          ),
        ),
        tenant.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(LySpace.x4),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => ListTile(
            key: const Key('organization_error'),
            leading: Icon(Icons.error_outline, color: c.danger),
            title: Text(l10n.organizationLoadError),
            trailing: TextButton(
              onPressed: () => ref.invalidate(tenantSettingsProvider),
              child: Text(l10n.commonRetry),
            ),
          ),
          data: (data) {
            _hydrate(data);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LyTextField(
                  key: const Key('organization_name'),
                  label: l10n.organizationNameLabel,
                  controller: _name,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: LySpace.x2),
                ListTile(
                  key: const Key('organization_timezone'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: Text(l10n.organizationTimezoneLabel),
                  subtitle: Text(
                    '${_timezone ?? data.timezone}\n'
                    '${l10n.organizationTimezoneHelp}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _saving ? null : _pickTimezone,
                ),
                const SizedBox(height: LySpace.x2),
                LyButton(
                  key: const Key('organization_save'),
                  label: l10n.commonSave,
                  loading: _saving,
                  onPressed: _saving || _name.text.trim().isEmpty
                      ? null
                      : _save,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Escolha de fuso: lista dos mais comuns com busca e a saída "Outro fuso…"
/// para digitar um nome IANA (o servidor valida; fuso inexistente volta como
/// `invalid_timezone`). Fecha com o nome escolhido.
class _TimezoneDialog extends StatefulWidget {
  const _TimezoneDialog({this.current});

  final String? current;

  @override
  State<_TimezoneDialog> createState() => _TimezoneDialogState();
}

class _TimezoneDialogState extends State<_TimezoneDialog> {
  final _query = TextEditingController();
  final _custom = TextEditingController();
  bool _other = false;

  @override
  void dispose() {
    _query.dispose();
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final needle = _query.text.trim().toLowerCase();
    final matches = commonTimezones
        .where((tz) => tz.toLowerCase().contains(needle))
        .toList();

    return AlertDialog(
      title: Text(l10n.organizationTimezoneLabel),
      content: SizedBox(
        width: 360,
        child: _other
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LyTextField(
                    key: const Key('timezone_custom'),
                    label: l10n.organizationTimezoneOtherLabel,
                    controller: _custom,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LyTextField(
                    key: const Key('timezone_search'),
                    label: l10n.organizationTimezoneSearchHint,
                    controller: _query,
                    prefixIcon: Icons.search,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: LySpace.x2),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final tz in matches)
                          ListTile(
                            key: Key('timezone_$tz'),
                            dense: true,
                            title: Text(tz),
                            trailing: tz == widget.current
                                ? const Icon(Icons.check)
                                : null,
                            onTap: () => Navigator.of(context).pop(tz),
                          ),
                        ListTile(
                          key: const Key('timezone_other'),
                          dense: true,
                          title: Text(l10n.organizationTimezoneOther),
                          onTap: () => setState(() => _other = true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        if (_other)
          TextButton(
            key: const Key('timezone_custom_confirm'),
            onPressed: _custom.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(_custom.text.trim()),
            child: Text(l10n.commonSave),
          ),
      ],
    );
  }
}
