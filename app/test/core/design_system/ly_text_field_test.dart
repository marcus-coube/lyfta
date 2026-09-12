import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';

/// `autofocus` existe por causa de um caso concreto: diálogo com o valor de
/// fábrica já no campo (título do novo plano). Sem foco na abertura, a seleção
/// inicial não vale e o que o professor digita **soma** ao default.
void main() {
  testWidgets('autofocus + texto selecionado faz a digitação substituir o valor', (tester) async {
    const initial = 'Treino A/B';
    final controller = TextEditingController.fromValue(
      const TextEditingValue(
        text: initial,
        selection: TextSelection(baseOffset: 0, extentOffset: initial.length),
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: LyTheme.dark(),
        home: Scaffold(
          body: LyTextField(label: 'Título', controller: controller, autofocus: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byType(TextField)).autofocus, isTrue);

    // enterText respeita o teclado do campo focado, então isto é a digitação
    // do professor sobre o texto selecionado, não um set no controller.
    await tester.enterText(find.byType(TextField), 'Plano do João');
    await tester.pump();

    expect(controller.text, 'Plano do João');
  });

  // P4.3 (a11y): o botão de mostrar/ocultar senha precisa de rótulo para
  // leitor de tela — sem isso o TalkBack só anuncia "botão".
  testWidgets('toggle de senha alterna o rótulo de acessibilidade ao tocar',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LyTheme.dark(),
        home: const Scaffold(
          body: LyTextField(
            label: 'Senha',
            obscure: true,
            showPasswordLabel: 'Mostrar senha',
            hidePasswordLabel: 'Ocultar senha',
          ),
        ),
      ),
    );

    expect(
      tester.widget<IconButton>(find.byType(IconButton)).tooltip,
      'Mostrar senha',
    );

    await tester.tap(find.byType(IconButton));
    await tester.pump();

    expect(
      tester.widget<IconButton>(find.byType(IconButton)).tooltip,
      'Ocultar senha',
    );
  });
}
