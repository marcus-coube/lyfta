import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/shared/money/money.dart';
import 'package:lyfta/shared/widgets/ly_money_field.dart';

Future<List<int?>> _pump(
  WidgetTester tester,
  Locale locale, {
  int? initial,
}) async {
  final changes = <int?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: LyTheme.dark(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: LyMoneyField(
          fieldKey: const Key('money'),
          label: 'Valor',
          cents: initial,
          onChanged: changes.add,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return changes;
}

String _text(WidgetTester tester) => tester
    .widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('money')),
        matching: find.byType(TextField),
      ),
    )
    .controller!
    .text;

void main() {
  testWidgets('pt-BR: "1.234,56" vira 123456 centavos', (tester) async {
    final changes = await _pump(tester, const Locale('pt'));

    await tester.enterText(find.byKey(const Key('money')), '1.234,56');
    await tester.pump();

    expect(changes.last, 123456);
    expect(_text(tester), '1.234,56');
  });

  testWidgets('en: "1,234.56" vira 123456 centavos', (tester) async {
    final changes = await _pump(tester, const Locale('en'));

    await tester.enterText(find.byKey(const Key('money')), '1,234.56');
    await tester.pump();

    expect(changes.last, 123456);
    expect(_text(tester), '1,234.56');
  });

  testWidgets('digitar só os dígitos aplica a máscara de moeda',
      (tester) async {
    final changes = await _pump(tester, const Locale('pt'));

    await tester.enterText(find.byKey(const Key('money')), '5');
    await tester.pump();
    expect(_text(tester), '0,05');
    expect(changes.last, 5);

    await tester.enterText(find.byKey(const Key('money')), '12000');
    await tester.pump();
    expect(_text(tester), '120,00');
    expect(changes.last, 12000);
  });

  testWidgets('valor inicial vem mascarado e apagar devolve null',
      (tester) async {
    final changes = await _pump(tester, const Locale('pt'), initial: 9990);
    expect(_text(tester), '99,90');

    await tester.enterText(find.byKey(const Key('money')), '');
    await tester.pump();
    expect(changes.last, isNull);
  });

  testWidgets('acima do teto a tecla é ignorada', (tester) async {
    final changes = await _pump(tester, const Locale('pt'), initial: 1000000000);
    expect(_text(tester), '10.000.000,00');

    await tester.enterText(find.byKey(const Key('money')), '100000000001');
    await tester.pump();
    expect(_text(tester), '10.000.000,00');
    expect(changes.where((c) => c != null && c > maxCents), isEmpty);
  });

  test('formatCents usa o idioma e nunca perde centavos', () {
    expect(formatCents(123456, 'pt').replaceAll(' ', ' '), 'R\$ 1.234,56');
    expect(formatCents(123456, 'en'), contains('1,234.56'));
    expect(formatCents(5, 'pt').replaceAll(' ', ' '), 'R\$ 0,05');
    expect(maskCents(100000000, 'pt'), '1.000.000,00');
    expect(parseCents('R\$ 1.234,56'), 123456);
    expect(parseCents(''), isNull);
  });
}
