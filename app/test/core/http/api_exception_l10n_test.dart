import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/http/api_exception.dart';
import 'package:lyfta/core/http/api_exception_l10n.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';

ApiException _tooMany(Object? seconds) => ApiException(
      code: 'too_many_requests',
      params: seconds == null ? const {} : {'retry_after_seconds': seconds},
      statusCode: 429,
    );

void main() {
  // Limite de tentativas (ADR-002 §2c): segundos do backend viram minutos
  // inteiros, arredondados para cima.
  group('too_many_requests', () {
    final pt = lookupAppLocalizations(const Locale('pt'));

    test('5 minutos do cooldown cheio', () {
      expect(
        _tooMany(300).message(pt),
        'Muitas tentativas. Aguarde 5 minutos e tente de novo.',
      );
    });

    test('arredonda para cima e usa o singular', () {
      expect(_tooMany(61).message(pt), contains('2 minutos'));
      expect(_tooMany(12).message(pt), contains('1 minuto '));
    });

    test('sem params assume o cooldown de 5 minutos', () {
      expect(_tooMany(null).message(pt), contains('5 minutos'));
    });

    test('pt-PT e en têm a própria frase', () {
      final ptPt = lookupAppLocalizations(
        const Locale.fromSubtags(languageCode: 'pt', countryCode: 'PT'),
      );
      final en = lookupAppLocalizations(const Locale('en'));
      expect(_tooMany(300).message(ptPt), startsWith('Demasiadas tentativas'));
      expect(_tooMany(300).message(en), startsWith('Too many attempts'));
    });
  });
}
