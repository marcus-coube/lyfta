import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/billing/data/billing_repository.dart';
import 'package:lyfta/features/billing/domain/billing_models.dart';
import 'package:lyfta/features/billing/presentation/billing_providers.dart';
import 'package:lyfta/features/billing/presentation/finance_screen.dart';

import 'billing_fakes.dart';

final l10n = lookupAppLocalizations(const Locale('pt'));

Future<FakeBillingRepository> _pump(
  WidgetTester tester, {
  BillingAccess access = BillingAccess.owner,
  List<Invoice>? invoices,
  List<BillingPlan>? plans,
  Size size = const Size(900, 1600),
}) async {
  final fake = FakeBillingRepository(
    invoices: invoices ??
        [
          testInvoice(id: 'inv-1', name: 'Ana Alves'),
          testInvoice(
            id: 'inv-2',
            studentId: 'aluno-2',
            name: 'Bruno Costa',
            status: 'overdue',
            amountCents: 99050,
            dueDate: DateTime(2026, 11, 5),
          ),
          testInvoice(
            id: 'inv-3',
            studentId: 'aluno-3',
            name: 'Carla Dias',
            status: 'paid',
          ),
        ],
    plans: plans,
  );
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        billingAccessProvider.overrideWithValue(access),
        billingRepositoryProvider.overrideWithValue(fake),
      ],
      child: MaterialApp(
        theme: LyTheme.dark(),
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: FinanceScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('lista mostra aluno, vencimento, valor em reais e status',
      (tester) async {
    await _pump(tester);

    expect(find.text('Ana Alves'), findsOneWidget);
    expect(find.text('Bruno Costa'), findsOneWidget);
    // R$ 990,50 vem de 99050 centavos; o separador depende do idioma.
    expect(find.textContaining('990,50'), findsOneWidget);
    expect(find.textContaining('120,00'), findsWidgets);
    expect(find.text('Em aberto'), findsWidgets);
    expect(find.text('Vencida'), findsWidgets);
    expect(find.text('Paga'), findsWidgets);
    // Tela larga vira tabela, com cabeçalho.
    expect(find.text(l10n.invoicesColStudent), findsOneWidget);
  });

  testWidgets('celular mostra cartões, não tabela', (tester) async {
    await _pump(tester, size: const Size(390, 900));

    expect(find.text('Ana Alves'), findsOneWidget);
    expect(find.text(l10n.invoicesColStudent), findsNothing);
  });

  testWidgets('filtro de status refaz a consulta no servidor', (tester) async {
    final fake = await _pump(tester);

    await tester.tap(find.byKey(const Key('invoices_filter_overdue')));
    await tester.pumpAndSettle();

    expect(fake.invoiceQueries.last['status'], 'overdue');
    expect(find.text('Bruno Costa'), findsOneWidget);
    expect(find.text('Ana Alves'), findsNothing);
  });

  testWidgets('dar baixa: confirma, manda chave de idempotência e quita',
      (tester) async {
    final fake = await _pump(tester);

    await tester.tap(find.byKey(const Key('invoice_pay_inv-2')));
    await tester.pumpAndSettle();
    // O diálogo diz quanto, de quem, e que quita por inteiro.
    expect(find.textContaining('Bruno Costa'), findsWidgets);
    expect(find.textContaining('990,50'), findsWidgets);

    await tester.enterText(find.byKey(const Key('pay_note')), 'PIX na conta');
    await tester.tap(find.byKey(const Key('pay_confirm')));
    await tester.pumpAndSettle();

    expect(fake.payments, hasLength(1));
    final (invoiceId, key, paidOn, note) = fake.payments.single;
    expect(invoiceId, 'inv-2');
    expect(key, isNotEmpty);
    // Hoje = "agora": o app não manda data.
    expect(paidOn, isNull);
    expect(note, 'PIX na conta');
    expect(find.text(l10n.payDone), findsOneWidget);
    // A fatura passou a paga: some "dar baixa", entra "estornar".
    expect(find.byKey(const Key('invoice_pay_inv-2')), findsNothing);
    expect(find.byKey(const Key('invoice_reverse_inv-2')), findsOneWidget);
  });

  testWidgets('estornar exige motivo e a fatura volta a vencida',
      (tester) async {
    final fake = await _pump(tester);

    await tester.tap(find.byKey(const Key('invoice_pay_inv-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pay_confirm')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('invoice_reverse_inv-2')));
    await tester.pumpAndSettle();

    // Sem motivo o botão não habilita.
    await tester.tap(
      find.byKey(const Key('reverse_confirm')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(fake.reversals, isEmpty);

    await tester.enterText(
      find.byKey(const Key('reverse_reason')),
      'Pagamento duplicado',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('reverse_confirm')));
    await tester.pumpAndSettle();

    expect(fake.reversals, [('pay-inv-2', 'Pagamento duplicado')]);
    // Voltou a vencida: dá para dar baixa de novo.
    expect(find.byKey(const Key('invoice_pay_inv-2')), findsOneWidget);
    expect(find.byKey(const Key('invoice_reverse_inv-2')), findsNothing);
  });

  testWidgets('coach own_students dá baixa mas não estorna e não vê planos',
      (tester) async {
    await _pump(tester, access: BillingAccess.coachOperator);

    expect(find.byKey(const Key('invoice_pay_inv-1')), findsOneWidget);
    // inv-3 está paga: sem "estornar" para o coach.
    expect(find.byKey(const Key('invoice_reverse_inv-3')), findsNothing);
    expect(find.text(l10n.billingTabPlans), findsNothing);
  });

  testWidgets('conta excluída aparece com nome, e-mail e selo', (tester) async {
    await _pump(
      tester,
      invoices: [
        testInvoice(id: 'inv-9', name: 'Dora Lima', accountDeleted: true),
      ],
    );

    expect(find.text('Dora Lima'), findsOneWidget);
    expect(
      find.textContaining(l10n.invoiceAccountDeleted),
      findsOneWidget,
    );
  });

  testWidgets('owner cria e arquiva plano de mensalidade', (tester) async {
    final fake = await _pump(tester);

    await tester.tap(find.text(l10n.billingTabPlans));
    await tester.pumpAndSettle();
    expect(find.text(l10n.billingPlansEmpty), findsOneWidget);

    await tester.tap(find.byKey(const Key('plan_new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('plan_name')), 'Mensal');
    await tester.enterText(find.byKey(const Key('plan_amount')), '1.234,56');
    await tester.pump();
    await tester.tap(find.byKey(const Key('plan_save')));
    await tester.pumpAndSettle();

    expect(fake.createdPlans, [('Mensal', 123456)]);
    expect(find.text('Mensal'), findsOneWidget);
    expect(find.textContaining('1.234,56'), findsOneWidget);

    await tester.tap(find.byKey(const Key('plan_archive_plan-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan_archive_confirm')));
    await tester.pumpAndSettle();

    expect(fake.archivedPlans, ['plan-1']);
    expect(find.text(l10n.billingPlansArchivedSection), findsOneWidget);
  });
}
