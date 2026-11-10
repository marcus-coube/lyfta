import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/billing/data/billing_repository.dart';
import 'package:lyfta/features/billing/domain/billing_models.dart';
import 'package:lyfta/features/billing/presentation/billing_providers.dart';
import 'package:lyfta/features/billing/presentation/delinquent_badge.dart';
import 'package:lyfta/features/billing/presentation/student_billing_tab.dart';

import 'billing_fakes.dart';

final l10n = lookupAppLocalizations(const Locale('pt'));

const _plan = BillingPlan(
  id: 'plan-mensal',
  name: 'Mensal',
  amountCents: 15000,
  currency: 'BRL',
  active: true,
);

Subscription _sub({String status = 'active'}) => Subscription(
      id: 'sub-9',
      studentId: 'aluno-1',
      billingPlanId: 'plan-mensal',
      amountCents: 15000,
      currency: 'BRL',
      dueDay: 10,
      startsOn: DateTime(2026, 10, 1),
      status: status,
      customer: const BillingCustomer(name: 'Ana Alves', email: 'a@x.com'),
    );

Future<FakeBillingRepository> _pump(
  WidgetTester tester, {
  List<Subscription>? subs,
  List<BillingPlan>? plans,
  List<Invoice>? invoices,
  BillingAccess access = BillingAccess.owner,
}) async {
  final fake = FakeBillingRepository(
    subscriptions: subs,
    plans: plans ?? [_plan],
    invoices: invoices ??
        [
          testInvoice(id: 'inv-1', status: 'overdue'),
          testInvoice(id: 'inv-0', period: '2026-10', status: 'paid'),
        ],
  );
  tester.view.physicalSize = const Size(900, 1600);
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
        home: const Scaffold(
          body: StudentBillingTab(
            studentId: 'aluno-1',
            studentName: 'Ana Alves',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('sem assinatura: cria com plano, valor do plano e vencimento',
      (tester) async {
    final fake = await _pump(tester);

    expect(find.text(l10n.subscriptionNone), findsOneWidget);
    // Histórico de faturas do aluno na mesma aba.
    expect(find.byKey(const Key('invoice_inv-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('subscription_create')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('subscription_plan')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Mensal').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('subscription_due_day')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('subscription_save')));
    await tester.pumpAndSettle();

    expect(fake.createdSubscriptions, hasLength(1));
    final created = fake.createdSubscriptions.single;
    expect(created['student'], 'aluno-1');
    expect(created['plan'], 'plan-mensal');
    // Valor igual ao do plano: o app não manda, o servidor usa o do plano.
    expect(created['amount'], isNull);
    expect(created['dueDay'], 15);
    expect(find.byKey(const Key('subscription_card')), findsOneWidget);
  });

  testWidgets('valor diferente do plano vai em centavos inteiros',
      (tester) async {
    final fake = await _pump(tester);

    await tester.tap(find.byKey(const Key('subscription_create')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('subscription_plan')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Mensal').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('subscription_amount')),
      '99,90',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('subscription_save')));
    await tester.pumpAndSettle();

    expect(fake.createdSubscriptions.single['amount'], 9990);
  });

  testWidgets('sem plano ativo explica o que fazer', (tester) async {
    await _pump(tester, plans: []);

    await tester.tap(find.byKey(const Key('subscription_create')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('subscription_no_plans')), findsOneWidget);
    expect(find.text(l10n.subscriptionNoPlansOwner), findsOneWidget);
    final save = tester.widget<TextButton>(
      find.byKey(const Key('subscription_save')),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('assinatura ativa: pausa, retoma e cancela com confirmação',
      (tester) async {
    final fake = await _pump(tester, subs: [_sub()]);

    expect(find.text('Ativa'), findsOneWidget);

    await tester.tap(find.byKey(const Key('subscription_pause')));
    await tester.pumpAndSettle();
    expect(fake.transitions.last, ('sub-9', 'pause'));
    expect(find.text('Pausada'), findsOneWidget);

    await tester.tap(find.byKey(const Key('subscription_resume')));
    await tester.pumpAndSettle();
    expect(fake.transitions.last, ('sub-9', 'resume'));

    await tester.tap(find.byKey(const Key('subscription_cancel')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.subscriptionCancelBody), findsOneWidget);
    await tester.tap(find.byKey(const Key('subscription_cancel_confirm')));
    await tester.pumpAndSettle();

    expect(fake.transitions.last, ('sub-9', 'cancel'));
    // Cancelada: volta a oferecer criar uma nova.
    expect(find.byKey(const Key('subscription_create')), findsOneWidget);
  });

  testWidgets('coach own_students não vê "estornar" no histórico',
      (tester) async {
    await _pump(tester, access: BillingAccess.coachOperator);

    expect(find.byKey(const Key('invoice_pay_inv-1')), findsOneWidget);
    expect(find.byKey(const Key('invoice_reverse_inv-0')), findsNothing);
  });

  testWidgets('selo inadimplente só aparece para quem deve', (tester) async {
    Future<void> pumpBadge(String? status, {Object? error}) async {
      final fake = FakeBillingRepository(
        statuses: {if (status != null) 'aluno-1': status},
      )..statusError = error;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [billingRepositoryProvider.overrideWithValue(fake)],
          child: MaterialApp(
            theme: LyTheme.dark(),
            locale: const Locale('pt'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: DelinquentBadge(studentId: 'aluno-1')),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpBadge('delinquent');
    expect(find.text(l10n.billingDelinquent), findsOneWidget);

    await pumpBadge('ok');
    expect(find.text(l10n.billingDelinquent), findsNothing);

    // billing fora do ar: sem selo, sem erro na tela.
    await pumpBadge(null, error: Exception('fora'));
    expect(find.text(l10n.billingDelinquent), findsNothing);
  });
}
