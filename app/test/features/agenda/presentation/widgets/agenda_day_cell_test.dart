import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/agenda/domain/agenda_day.dart';
import 'package:lyfta/features/agenda/presentation/widgets/agenda_day_cell.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: LyTheme.dark(),
    locale: const Locale('pt'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  // Aceite do P4.1: "teste de widget da célula de dia nos 3 estados
  // (previsto / feito / descanso)". A célula é um widget "burro" — nenhum
  // dos três casos sobe controller ou repositório.
  testWidgets('dia feito mostra o indicador preenchido com o check',
      (tester) async {
    await tester.pumpWidget(
      _host(
        AgendaDayCell(
          date: DateTime(2026, 9, 8),
          state: AgendaDayState.done,
          label: 'A',
        ),
      ),
    );

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.remove_rounded), findsNothing);
    // O rótulo do rodízio não é escrito dentro do indicador de "feito" (o
    // check já diz que aconteceu); só o dia do mês aparece como texto.
    expect(find.text('A'), findsNothing);
    expect(find.text('8'), findsOneWidget);
  });

  testWidgets('dia previsto mostra o rótulo do rodízio num círculo aberto',
      (tester) async {
    await tester.pumpWidget(
      _host(
        AgendaDayCell(
          date: DateTime(2026, 9, 9),
          state: AgendaDayState.predicted,
          label: 'B',
        ),
      ),
    );

    expect(find.text('B'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(find.byIcon(Icons.remove_rounded), findsNothing);
  });

  testWidgets('dia de descanso não mostra rótulo nem check', (tester) async {
    await tester.pumpWidget(
      _host(
        AgendaDayCell(
          date: DateTime(2026, 9, 10),
          state: AgendaDayState.rest,
        ),
      ),
    );

    expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
  });

  testWidgets('toque na célula dispara o callback', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _host(
        AgendaDayCell(
          date: DateTime(2026, 9, 8),
          state: AgendaDayState.done,
          label: 'A',
          onTap: () => tapped = true,
        ),
      ),
    );

    await tester.tap(find.byType(AgendaDayCell));
    expect(tapped, isTrue);
  });
}
