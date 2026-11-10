import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/billing/data/billing_repository.dart';
import 'package:lyfta/features/billing/presentation/my_invoices_screen.dart';

import 'billing_fakes.dart';

final l10n = lookupAppLocalizations(const Locale('pt'));

Future<void> _pump(WidgetTester tester, FakeBillingRepository fake) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [billingRepositoryProvider.overrideWithValue(fake)],
      child: MaterialApp(
        theme: LyTheme.dark(),
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const MyInvoicesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('aluno vê as próprias faturas, só leitura, com status',
      (tester) async {
    await _pump(
      tester,
      FakeBillingRepository(
        invoices: [
          testInvoice(id: 'a', status: 'overdue'),
          testInvoice(id: 'b', period: '2026-10', status: 'paid'),
        ],
      ),
    );

    expect(find.byKey(const Key('my_invoice_a')), findsOneWidget);
    expect(find.text('Vencida'), findsOneWidget);
    expect(find.text('Paga'), findsOneWidget);
    expect(find.textContaining('120,00'), findsNWidgets(2));
    // Nenhuma ação: baixa e estorno são do financeiro.
    expect(find.text(l10n.invoiceActionPay), findsNothing);
    expect(find.text(l10n.invoiceActionReverse), findsNothing);
  });

  testWidgets('sem faturas mostra o estado vazio', (tester) async {
    await _pump(tester, FakeBillingRepository());
    expect(find.text(l10n.myInvoicesEmpty), findsOneWidget);
  });
}
