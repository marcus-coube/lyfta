import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/workout/domain/today.dart';
import 'package:lyfta/features/workout/domain/workout_event.dart';
import 'package:lyfta/features/workout/presentation/widgets/set_row.dart';
import 'package:lyfta/shared/domain/plan.dart';

/// O que o `onLog` recebeu — é o contrato entre a linha e o controller.
class _Captured {
  int? reps;
  double? load;
  String? revises;
  int calls = 0;
}

Widget _host(Widget child) {
  return MaterialApp(
    theme: LyTheme.dark(),
    locale: const Locale('pt'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  late _Captured captured;

  setUp(() => captured = _Captured());

  Future<void> onLog(int? reps, double? load, String? revises) async {
    captured
      ..reps = reps
      ..load = load
      ..revises = revises;
    captured.calls++;
  }

  testWidgets('vem pré-preenchida: reps da prescrição, carga da última vez',
      (tester) async {
    await tester.pumpWidget(
      _host(
        SetRow(
          setNo: 1,
          prescribed: PrescribedSet(repsMin: 8, repsMax: 12, targetLoadKg: 30),
          previous: const PreviousLoadSet(setNo: 1, repsDone: 10, loadKg: 42.5),
          onLog: onLog,
        ),
      ),
    );

    // Reps saem da prescrição (topo da faixa); a carga sai do que ele
    // levantou da última vez, não do alvo do professor. Vírgula é o
    // separador decimal em pt-BR (ADR-011 §4) — nunca o ponto de um
    // `toString()` cru.
    expect(find.widgetWithText(TextField, '12'), findsOneWidget);
    expect(find.widgetWithText(TextField, '42,5'), findsOneWidget);
  });

  testWidgets('registrar série manda o que está nos campos', (tester) async {
    await tester.pumpWidget(
      _host(
        SetRow(
          setNo: 2,
          prescribed: PrescribedSet(repsMin: 10, repsMax: 10),
          onLog: onLog,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).last, '47,5');
    await tester.tap(find.byIcon(Icons.check_circle_outline));
    await tester.pumpAndSettle();

    expect(captured.calls, 1);
    expect(captured.reps, 10);
    // Vírgula é o separador decimal em pt-BR: teclado do aluno manda vírgula.
    expect(captured.load, 47.5);
    expect(captured.revises, isNull);
  });

  testWidgets('em tela estreita a série quebra em duas linhas', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        SetRow(
          setNo: 1,
          prescribed: PrescribedSet(repsMin: 8, repsMax: 12, targetLoadKg: 30),
          onLog: onLog,
        ),
      ),
    );

    // Os dois campos continuam inteiros — no layout de uma linha só eles
    // ficariam com ~70px e o rótulo flutuante da carga não caberia.
    final l10n = lookupAppLocalizations(const Locale('pt'));
    expect(find.text(l10n.sessionLoadKg), findsOneWidget);
    expect(tester.takeException(), isNull);

    final reps = tester.getRect(find.byType(TextField).first);
    final label = tester.getRect(find.text(l10n.sessionSet(1)));
    expect(reps.top, greaterThan(label.bottom));
  });

  testWidgets('série já registrada mostra o resumo e corrige por revisão',
      (tester) async {
    final logged = LocalSetLog(
      clientId: 'log-1',
      sessionClientId: 'session-1',
      exerciseId: 'ex-1',
      setNo: 1,
      performedAt: DateTime.utc(2026, 8, 31),
      repsDone: 10,
      loadKg: 40,
    );
    await tester.pumpWidget(
      _host(
        SetRow(
          setNo: 1,
          prescribed: PrescribedSet(repsMin: 10, repsMax: 10),
          logged: logged,
          onLog: onLog,
        ),
      ),
    );

    final l10n = lookupAppLocalizations(const Locale('pt'));
    expect(find.text(l10n.sessionLoggedSet('10', '40')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '8');
    await tester.tap(find.text(l10n.commonSave));
    await tester.pumpAndSettle();

    expect(captured.reps, 8);
    // Corrigir nunca edita o fato: vira revisão do log original (ADR-003 §5).
    expect(captured.revises, 'log-1');
  });

  testWidgets('carga acima de 1.000 kg não registra e marca o campo (A9)',
      (tester) async {
    await tester.pumpWidget(
      _host(
        SetRow(
          setNo: 1,
          prescribed: PrescribedSet(repsMin: 10, repsMax: 10),
          onLog: onLog,
        ),
      ),
    );

    final l10n = lookupAppLocalizations(const Locale('pt'));
    await tester.enterText(find.byType(TextField).last, '5255,5');
    await tester.tap(find.byIcon(Icons.check_circle_outline));
    await tester.pumpAndSettle();

    // O servidor rejeitaria e a fila descartaria sem aviso: nem chega a sair.
    expect(captured.calls, 0);
    expect(find.text(l10n.sessionLoadOutOfRange), findsOneWidget);

    // Mexer no campo limpa o erro; valor válido registra normalmente.
    await tester.enterText(find.byType(TextField).last, '55');
    await tester.pump();
    expect(find.text(l10n.sessionLoadOutOfRange), findsNothing);
    await tester.tap(find.byIcon(Icons.check_circle_outline));
    await tester.pumpAndSettle();
    expect(captured.calls, 1);
    expect(captured.load, 55);
  });

  testWidgets('correção fora do limite não fecha o diálogo (A9)',
      (tester) async {
    final logged = LocalSetLog(
      clientId: 'log-1',
      sessionClientId: 'session-1',
      exerciseId: 'ex-1',
      setNo: 1,
      performedAt: DateTime.utc(2026, 8, 31),
      repsDone: 10,
      loadKg: 52.5,
    );
    await tester.pumpWidget(
      _host(
        SetRow(
          setNo: 1,
          prescribed: PrescribedSet(repsMin: 10, repsMax: 10),
          logged: logged,
          onLog: onLog,
        ),
      ),
    );

    final l10n = lookupAppLocalizations(const Locale('pt'));
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '1001');
    await tester.enterText(find.byType(TextField).last, '1000,5');
    await tester.tap(find.text(l10n.commonSave));
    await tester.pumpAndSettle();

    expect(captured.calls, 0);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(l10n.sessionRepsOutOfRange), findsOneWidget);
    expect(find.text(l10n.sessionLoadOutOfRange), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '10');
    await tester.enterText(find.byType(TextField).last, '1000');
    await tester.tap(find.text(l10n.commonSave));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(captured.calls, 1);
    expect(captured.load, 1000);
    expect(captured.revises, 'log-1');
  });
}
