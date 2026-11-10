import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../domain/billing_models.dart';
import 'billing_format.dart';
import 'billing_providers.dart';
import 'invoice_actions.dart';

/// Ações da linha: "dar baixa" nas em aberto/vencidas (owner e coach
/// `own_students`) e "estornar" nas pagas (só owner).
class _InvoiceActions extends ConsumerWidget {
  const _InvoiceActions({required this.invoice, required this.access});

  final Invoice invoice;
  final BillingAccess access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (access.canOperate && invoice.isPayable) {
      return TextButton(
        key: Key('invoice_pay_${invoice.id}'),
        onPressed: () => recordPaymentFlow(context, ref, invoice),
        child: Text(l10n.invoiceActionPay),
      );
    }
    if (access.isOwner && invoice.isPaid) {
      return TextButton(
        key: Key('invoice_reverse_${invoice.id}'),
        onPressed: () => reversePaymentFlow(context, ref, invoice),
        child: Text(l10n.invoiceActionReverse),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Cartão da fatura (celular e ficha do aluno).
class InvoiceTile extends StatelessWidget {
  const InvoiceTile({
    required this.invoice,
    required this.access,
    this.showCustomer = true,
    super.key,
  });

  final Invoice invoice;
  final BillingAccess access;

  /// Falso na ficha do aluno (o titular já é o título da tela).
  final bool showCustomer;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return LyCard(
      key: Key('invoice_${invoice.id}'),
      padding: const EdgeInsets.all(LySpace.x4),
      onTap: () => showInvoiceDetail(context, invoice.id, access),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  showCustomer
                      ? invoice.customer.name
                      : periodText(context, invoice.period),
                  style: LyType.label(c.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              InvoiceStatusChip(status: invoice.status),
            ],
          ),
          if (showCustomer && invoice.customer.accountDeleted)
            Text(
              l10n.invoiceAccountDeleted,
              style: LyType.caption(c.warning),
            ),
          const SizedBox(height: LySpace.x1),
          Text(
            moneyText(context, invoice.amountCents, currency: invoice.currency),
            style: LyType.numeric(c.textPrimary),
          ),
          Text(
            l10n.invoiceDueOn(dayText(context, invoice.dueDate)),
            style: LyType.caption(c.textSecondary),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: _InvoiceActions(invoice: invoice, access: access),
          ),
        ],
      ),
    );
  }
}

const _colStudent = 4;
const _colDue = 2;
const _colAmount = 2;
const _colStatus = 2;

/// Títulos da tabela de faturas (tela larga).
class InvoiceTableHeader extends StatelessWidget {
  const InvoiceTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = LyType.caption(context.ly.textSecondary);
    return Padding(
      padding: const EdgeInsets.fromLTRB(LySpace.x4, LySpace.x2, LySpace.x4, 0),
      child: Row(
        children: [
          Expanded(
              flex: _colStudent,
              child: Text(l10n.invoicesColStudent, style: style),),
          Expanded(
              flex: _colDue, child: Text(l10n.invoicesColDue, style: style),),
          Expanded(
              flex: _colAmount,
              child: Text(l10n.invoicesColAmount, style: style),),
          Expanded(
              flex: _colStatus,
              child: Text(l10n.invoicesColStatus, style: style),),
          // Espaço da ação.
          const SizedBox(width: 120),
        ],
      ),
    );
  }
}

/// Linha da tabela de faturas (tela larga): aluno, vencimento, valor, status.
class InvoiceTableRow extends StatelessWidget {
  const InvoiceTableRow({
    required this.invoice,
    required this.access,
    super.key,
  });

  final Invoice invoice;
  final BillingAccess access;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return LyCard(
      key: Key('invoice_${invoice.id}'),
      padding: const EdgeInsets.symmetric(
        horizontal: LySpace.x4,
        vertical: LySpace.x2,
      ),
      onTap: () => showInvoiceDetail(context, invoice.id, access),
      child: Row(
        children: [
          Expanded(
            flex: _colStudent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invoice.customer.name,
                  style: LyType.label(c.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  invoice.customer.accountDeleted
                      ? '${invoice.customer.email} · ${l10n.invoiceAccountDeleted}'
                      : invoice.customer.email,
                  style: LyType.caption(
                    invoice.customer.accountDeleted
                        ? c.warning
                        : c.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Expanded(
            flex: _colDue,
            child: Text(
              dayText(context, invoice.dueDate),
              style: LyType.body(c.textSecondary),
            ),
          ),
          Expanded(
            flex: _colAmount,
            child: Text(
              moneyText(context, invoice.amountCents,
                  currency: invoice.currency,),
              style: LyType.body(c.textPrimary),
            ),
          ),
          Expanded(
            flex: _colStatus,
            child: Align(
              alignment: Alignment.centerLeft,
              child: InvoiceStatusChip(status: invoice.status),
            ),
          ),
          SizedBox(
            width: 120,
            child: Align(
              alignment: Alignment.centerRight,
              child: _InvoiceActions(invoice: invoice, access: access),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rodapé das listas de faturas: pede a próxima página ao ser construído; se
/// a página falhar, oferece "tentar de novo" em vez de repetir sozinho.
class InvoiceLoadMoreFooter extends ConsumerStatefulWidget {
  const InvoiceLoadMoreFooter(
      {required this.query, required this.state, super.key,});

  final InvoiceQuery query;
  final InvoiceListState state;

  @override
  ConsumerState<InvoiceLoadMoreFooter> createState() =>
      _InvoiceLoadMoreFooterState();
}

class _InvoiceLoadMoreFooterState extends ConsumerState<InvoiceLoadMoreFooter> {
  void _maybeLoad() {
    final s = widget.state;
    if (s.loadingMore || s.loadMoreFailed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(invoiceListProvider(widget.query).notifier).loadMore();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _maybeLoad();
  }

  @override
  void didUpdateWidget(InvoiceLoadMoreFooter old) {
    super.didUpdateWidget(old);
    _maybeLoad();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (widget.state.loadMoreFailed) {
      return Center(
        child: TextButton(
          onPressed: () =>
              ref.read(invoiceListProvider(widget.query).notifier).loadMore(),
          child: Text(l10n.commonRetry),
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.all(LySpace.x4),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}
