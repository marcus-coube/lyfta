import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/evolution/domain/evolution_summary.dart';
import 'package:lyfta/features/evolution/widgets/summary_card.dart';

Future<void> _pump(WidgetTester tester, EvolutionSummary summary) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: LyTheme.dark(),
      locale: const Locale('pt'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(child: SummaryCard(summary: summary)),
      ),
    ),
  );
}

void main() {
  testWidgets('lesão ativa e objetivo aparecem no resumo do coach',
      (tester) async {
    final summary = EvolutionSummary.fromJson({
      'photo_count': 0,
      'goal': 'hypertrophy',
      'active_injuries': [
        {
          'id': 'i1',
          'body_region': 'lower_back',
          'description': 'Hérnia L5',
          'created_at': '2026-11-01T10:00:00Z',
        },
      ],
    });
    await _pump(tester, summary);

    expect(find.text('Hipertrofia'), findsOneWidget);
    expect(find.text('Lombar: Hérnia L5'), findsOneWidget);
  });

  testWidgets('sem anamnese mostra os estados vazios', (tester) async {
    await _pump(
      tester,
      EvolutionSummary.fromJson({'photo_count': 0}),
    );

    expect(find.text('Objetivo não informado'), findsOneWidget);
    expect(find.text('Sem lesões ativas'), findsOneWidget);
  });
}
