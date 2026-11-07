import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/legal/legal_document.dart';

/// As escolhas de consentimento do ADR-008 §1, compartilhadas pelo aceite de
/// convite e pela tela de consentimento (gate): aceite dos termos (sempre),
/// dados de saúde (obrigatório para o aluno) e fotos de evolução (opcional).
///
/// É controlado de fora: quem usa guarda os três valores e decide quando o
/// botão de continuar habilita (`termsAccepted && (!showHealthData ||
/// healthData)`).
class ConsentChoices extends StatelessWidget {
  const ConsentChoices({
    required this.termsAccepted,
    required this.healthData,
    required this.progressPhotos,
    required this.onTermsChanged,
    required this.onHealthDataChanged,
    required this.onProgressPhotosChanged,
    this.showHealthData = true,
    super.key,
  });

  final bool termsAccepted;
  final bool healthData;
  final bool progressPhotos;
  final ValueChanged<bool> onTermsChanged;
  final ValueChanged<bool> onHealthDataChanged;
  final ValueChanged<bool> onProgressPhotosChanged;

  /// Coach/owner não consentem finalidades de saúde (só os termos).
  final bool showHealthData;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ConsentTile(
          key: const Key('consent_terms'),
          value: termsAccepted,
          onChanged: onTermsChanged,
          title: l10n.consentTermsAccept,
        ),
        Wrap(
          children: [
            TextButton(
              onPressed: () => showLegalDocument(context, LegalDocument.terms),
              child: Text(l10n.consentReadTerms),
            ),
            TextButton(
              onPressed: () =>
                  showLegalDocument(context, LegalDocument.privacy),
              child: Text(l10n.consentReadPrivacy),
            ),
          ],
        ),
        if (showHealthData) ...[
          const SizedBox(height: LySpace.x3),
          _ConsentTile(
            key: const Key('consent_health_data'),
            value: healthData,
            onChanged: onHealthDataChanged,
            title: l10n.consentHealthDataTitle,
            body: l10n.consentHealthDataBody,
          ),
          const SizedBox(height: LySpace.x3),
          _ConsentTile(
            key: const Key('consent_progress_photos'),
            value: progressPhotos,
            onChanged: onProgressPhotosChanged,
            title: l10n.consentPhotosTitle,
            body: l10n.consentPhotosBody,
          ),
        ],
        const SizedBox(height: LySpace.x2),
        Text(l10n.consentRequiredHint, style: LyType.caption(c.textSecondary)),
      ],
    );
  }
}

class _ConsentTile extends StatelessWidget {
  const _ConsentTile({
    required this.value,
    required this.onChanged,
    required this.title,
    this.body,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    return CheckboxListTile(
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(title, style: LyType.title(c.textPrimary)),
      subtitle: body == null
          ? null
          : Text(body!, style: LyType.bodySm(c.textSecondary)),
    );
  }
}
