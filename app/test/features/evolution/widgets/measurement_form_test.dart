import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/evolution/domain/measurement.dart';
import 'package:lyfta/features/evolution/widgets/measurement_form.dart';

/// Monta o form isolado, com tema e i18n reais — mesmo padrão do
/// `set_editor_test.dart` (P1.6).
Future<void> _pumpForm(
  WidgetTester tester, {
  required ValueChanged<MeasurementDraft> onSubmit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: LyTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(child: MeasurementForm(onSubmit: onSubmit)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _fieldInput(String field) => find.descendant(
      of: find.byKey(Key('measurement-form-$field')),
      matching: find.byType(TextField),
    );

void main() {
  testWidgets(
      'preenchimento parcial — só o peso — chama onSubmit com o rascunho',
      (tester) async {
    MeasurementDraft? submitted;
    await _pumpForm(tester, onSubmit: (draft) => submitted = draft);

    await tester.enterText(_fieldInput('weight_kg'), '82.5');
    await tester.ensureVisible(find.byKey(const Key('measurement-form-save')));
    await tester.tap(find.byKey(const Key('measurement-form-save')));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.weightKg, 82.5);
    expect(submitted!.heightCm, isNull);
    expect(submitted!.hasAnyValue, isTrue);
    // Nenhum erro de validação visível quando ao menos um campo foi
    // preenchido — "parcial ok" do Aceite.
    final l10n =
        AppLocalizations.of(tester.element(find.byType(MeasurementForm)));
    expect(find.text(l10n.measurementFormEmpty), findsNothing);
  });

  testWidgets(
      'preenchimento parcial em vários campos entra só com o que foi digitado',
      (tester) async {
    MeasurementDraft? submitted;
    await _pumpForm(tester, onSubmit: (draft) => submitted = draft);

    await tester.enterText(_fieldInput('waist_cm'), '81');
    await tester.enterText(_fieldInput('hip_cm'), '99,5');
    await tester.ensureVisible(find.byKey(const Key('measurement-form-save')));
    await tester.tap(find.byKey(const Key('measurement-form-save')));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.waistCm, 81);
    // Vírgula decimal (pt-BR) é aceita como separador.
    expect(submitted!.hipCm, 99.5);
    expect(submitted!.weightKg, isNull);
  });

  testWidgets(
      'formulário vazio é bloqueado — onSubmit não dispara e mostra o erro',
      (tester) async {
    var called = false;
    await _pumpForm(tester, onSubmit: (_) => called = true);

    await tester.ensureVisible(find.byKey(const Key('measurement-form-save')));
    await tester.tap(find.byKey(const Key('measurement-form-save')));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    final l10n =
        AppLocalizations.of(tester.element(find.byType(MeasurementForm)));
    expect(find.text(l10n.measurementFormEmpty), findsOneWidget);
  });

  testWidgets(
      'preencher só as observações ainda é bloqueado — não é uma medida',
      (tester) async {
    var called = false;
    await _pumpForm(tester, onSubmit: (_) => called = true);

    await tester.enterText(find.byType(TextField).last, 'Sem balança hoje');
    await tester.ensureVisible(find.byKey(const Key('measurement-form-save')));
    await tester.tap(find.byKey(const Key('measurement-form-save')));
    await tester.pumpAndSettle();

    expect(called, isFalse);
  });
}
