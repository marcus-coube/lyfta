import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/gen/app_localizations.dart';

/// Os dois documentos versionados do ADR-008 §6.
enum LegalDocument { terms, privacy }

/// Nome do arquivo em `assets/legal/` para o idioma ativo. pt-BR é a língua
/// fonte; pt-PT e en têm tradução própria (ADR-011).
String legalAssetPath(LegalDocument doc, Locale locale) {
  final name = switch (doc) {
    LegalDocument.terms => 'terms',
    LegalDocument.privacy => 'privacy',
  };
  final suffix = switch ((locale.languageCode, locale.countryCode)) {
    ('pt', 'PT') => 'pt-PT',
    ('pt', _) => 'pt-BR',
    _ => 'en',
  };
  return 'assets/legal/${name}_$suffix.md';
}

/// Abre o documento num diálogo rolável, sem sair da tela atual — usado no
/// aceite de convite, no signup, no gate de consentimento e na tela Conta.
Future<void> showLegalDocument(BuildContext context, LegalDocument doc) {
  final path = legalAssetPath(doc, Localizations.localeOf(context));
  return showDialog<void>(
    context: context,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      return AlertDialog(
        content: SizedBox(
          width: 520,
          child: FutureBuilder<String>(
            future: rootBundle.loadString(path),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text(l10n.legalLoadError);
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return SingleChildScrollView(
                child: SelectableText(snapshot.data!),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.legalClose),
          ),
        ],
      );
    },
  );
}
