import 'dart:ui';

import 'package:flutter/widgets.dart' show basicLocaleListResolution;

import '../l10n/gen/app_localizations.dart';

/// Locale do device resolvido do mesmo jeito que `MaterialApp.router`
/// resolveria (`main.dart` não passa `localeListResolutionCallback`, então
/// usa o padrão do Flutter, `basicLocaleListResolution`) — é assim que
/// `POST /v1/devices` (P3.4) manda o idioma que a UI realmente está usando,
/// não o idioma cru do sistema operacional (que pode não estar entre os três
/// suportados, ADR-011 §1).
///
/// Função pura (sem `BuildContext`) para poder rodar antes de qualquer tela
/// existir, no boot da sessão — dívida do P1.8 fechada aqui só para o
/// registro de device: o restante do app (conteúdo dinâmico do backend)
/// ainda não manda `?locale=` nas outras chamadas.
Locale resolveDeviceLocale() {
  return basicLocaleListResolution(
    PlatformDispatcher.instance.locales,
    AppLocalizations.supportedLocales,
  );
}

/// Traduz um [Locale] resolvido para o código que o `comms` aceita em
/// `device_tokens.locale` (`domain.IsValidLocale`, P3.4): `pt-BR`, `pt-PT`
/// ou `en`.
String backendLocaleCode(Locale locale) {
  if (locale.languageCode != 'pt') return 'en';
  return locale.countryCode == 'PT' ? 'pt-PT' : 'pt-BR';
}
