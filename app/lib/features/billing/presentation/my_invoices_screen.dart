import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/ly_error_state.dart';
import '../../../shared/widgets/ly_skeleton.dart';
import '../domain/billing_models.dart';
import 'billing_format.dart';
import 'billing_providers.dart';
import 'invoice_widgets.dart';

const _mine = InvoiceQuery(mine: true);

/// "Minhas mensalidades" (aluno, pela Conta): as próprias faturas, somente
/// leitura — pagar e dar baixa é com o professor/organização.
class MyInvoicesScreen extends ConsumerWidget {
  const MyInvoicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final invoices = ref.watch(invoiceListProvider(_mine));

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: Text(l10n.accountInvoicesTitle)),
      body: SafeArea(
        child: invoices.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(LySpace.x4),
            child: Column(
              children: [
                LySkeletonListTile(),
                SizedBox(height: LySpace.x3),
                LySkeletonListTile(),
              ],
            ),
          ),
          error: (error, _) => LyErrorState(
            message: describeApiError(context, error),
            retryable: isRetryableError(error),
            onRetry: () => ref.invalidate(invoiceListProvider(_mine)),
          ),
          data: (state) {
            if (state.items.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(LySpace.x4),
                  child: Text(
                    l10n.myInvoicesEmpty,
                    style: LyType.body(c.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final footer = state.hasMore ? 1 : 0;
            return ListView.builder(
              padding: const EdgeInsets.all(LySpace.x4),
              itemCount: state.items.length + footer,
              itemBuilder: (context, i) {
                if (i >= state.items.length) {
                  return InvoiceLoadMoreFooter(query: _mine, state: state);
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: LySpace.x2),
                  child: _MyInvoiceTile(invoice: state.items[i]),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _MyInvoiceTile extends StatelessWidget {
  const _MyInvoiceTile({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final paidAt = invoice.paidAt;

    return LyCard(
      key: Key('my_invoice_${invoice.id}'),
      padding: const EdgeInsets.all(LySpace.x4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  periodText(context, invoice.period),
                  style: LyType.label(c.textPrimary),
                ),
                Text(
                  moneyText(context, invoice.amountCents,
                      currency: invoice.currency,),
                  style: LyType.numeric(c.textPrimary),
                ),
                Text(
                  paidAt != null && invoice.isPaid
                      ? l10n.invoicePaidOn(dayText(context, paidAt))
                      : l10n.invoiceDueOn(dayText(context, invoice.dueDate)),
                  style: LyType.caption(c.textSecondary),
                ),
              ],
            ),
          ),
          InvoiceStatusChip(status: invoice.status),
        ],
      ),
    );
  }
}
