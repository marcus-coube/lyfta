import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/config/app_config.dart';
import 'package:lyfta/core/legal/legal_document.dart';

/// ADR-008 §6: os termos são versionados no repo, nos 3 idiomas, e a versão
/// dentro de cada texto é a que o app manda ao backend (`TERMS_VERSION`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const locales = [Locale('pt'), Locale('pt', 'PT'), Locale('en')];

  for (final doc in LegalDocument.values) {
    for (final locale in locales) {
      test('${doc.name} em $locale existe e declara a versão vigente',
          () async {
        final text = await rootBundle.loadString(legalAssetPath(doc, locale));
        expect(text.trim(), isNotEmpty);
        expect(text, contains(AppConfig.termsVersion));
      });
    }
  }

  test('pt cai em pt-BR, pt-PT em pt-PT e o resto em en', () {
    expect(
      legalAssetPath(LegalDocument.terms, const Locale('pt')),
      endsWith('terms_pt-BR.md'),
    );
    expect(
      legalAssetPath(LegalDocument.privacy, const Locale('pt', 'PT')),
      endsWith('privacy_pt-PT.md'),
    );
    expect(
      legalAssetPath(LegalDocument.terms, const Locale('fr')),
      endsWith('terms_en.md'),
    );
  });
}
