import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/auth/presentation/signup_screen.dart';

/// O E2E do P1.8 encontrou um tenant com o slug
/// `academia-e2eacademia-academia-e2eacademia-e2ee2e`, e a suspeita era o
/// espelhamento nome→slug acumulando a cada tecla. Estes testes digitam
/// letra a letra (é assim que o `onChanged` dispara de verdade) para separar
/// defeito do app de digitação torta na hora do roteiro.
final _theme = LyTheme.dark();

Widget _app() {
  return ProviderScope(
    child: MaterialApp(
      theme: _theme,
      locale: const Locale('pt'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SignupScreen(),
    ),
  );
}

Future<void> _typeLetterByLetter(WidgetTester tester, Finder field, String text) async {
  for (var i = 1; i <= text.length; i++) {
    await tester.enterText(field, text.substring(0, i));
    await tester.pump();
  }
}

void main() {
  testWidgets('nome digitado letra a letra gera o slug uma vez só', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await _typeLetterByLetter(tester, fields.at(0), 'Academia E2E');

    expect(tester.widget<TextField>(fields.at(1)).controller!.text, 'academia-e2e');
  });

  testWidgets('slug editado à mão para de espelhar o nome', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await _typeLetterByLetter(tester, fields.at(0), 'Academia');
    await tester.enterText(fields.at(1), 'minha-academia');
    await tester.pump();
    await _typeLetterByLetter(tester, fields.at(0), 'Academia Nova');

    expect(tester.widget<TextField>(fields.at(1)).controller!.text, 'minha-academia');
  });
}
