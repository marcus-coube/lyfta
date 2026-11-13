import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/variations/data/variation_repository.dart';
import 'package:lyfta/features/variations/presentation/variations_screen.dart';
import 'package:lyfta/shared/domain/plan.dart';

import 'fake_variations.dart';

Future<AppLocalizations> _pump(WidgetTester tester, FakeVariations fake) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [variationRepositoryProvider.overrideWithValue(fake)],
      child: MaterialApp(
        theme: LyTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const VariationsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return AppLocalizations.of(tester.element(find.byType(VariationsScreen)));
}

void main() {
  testWidgets('cria uma variação e ela aparece na lista', (tester) async {
    final fake = FakeVariations();
    await _pump(tester, fake);

    await tester.tap(find.byKey(const Key('variation_new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('variation_name')), 'Pausa no fundo');
    await tester.enterText(
      find.byKey(const Key('variation_description')),
      'Segure 2 s embaixo.',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('variation_save')));
    await tester.pumpAndSettle();

    expect(fake.items.single.name, 'Pausa no fundo');
    expect(find.text('Pausa no fundo'), findsOneWidget);
    expect(find.text('Segure 2 s embaixo.'), findsOneWidget);
  });

  testWidgets('nome duplicado vira mensagem i18n no campo e o diálogo segue aberto',
      (tester) async {
    final fake = FakeVariations(
      [const SetVariation(id: 'a', name: 'Pausa no fundo')],
    );
    final l10n = await _pump(tester, fake);

    await tester.tap(find.byKey(const Key('variation_new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('variation_name')), 'pausa no fundo');
    await tester.pump();
    await tester.tap(find.byKey(const Key('variation_save')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.errorVariationNameTaken), findsOneWidget);
    expect(find.byKey(const Key('variation_save')), findsOneWidget);
    expect(fake.items.length, 1);
  });

  testWidgets('arquivar tira da lista; o filtro mostra as arquivadas e dá para desarquivar',
      (tester) async {
    final fake = FakeVariations(
      [const SetVariation(id: 'a', name: 'Pausa no fundo')],
    );
    await _pump(tester, fake);

    await tester.tap(find.byKey(const Key('variation_archive_a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('variation_a')), findsNothing);
    expect(fake.items.single.archived, isTrue);

    await tester.tap(find.byKey(const Key('variation_show_archived')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('variation_a')), findsOneWidget);

    await tester.tap(find.byKey(const Key('variation_archive_a')));
    await tester.pumpAndSettle();
    expect(fake.items.single.archived, isFalse);
  });

  testWidgets('editar muda nome e descrição', (tester) async {
    final fake = FakeVariations(
      [const SetVariation(id: 'a', name: 'Pausa')],
    );
    await _pump(tester, fake);

    await tester.tap(find.byKey(const Key('variation_a')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('variation_name')), 'Pausa 2s');
    await tester.pump();
    await tester.tap(find.byKey(const Key('variation_save')));
    await tester.pumpAndSettle();

    expect(fake.items.single.name, 'Pausa 2s');
  });
}
