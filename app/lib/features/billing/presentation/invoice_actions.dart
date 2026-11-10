import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/ly_date_field.dart';
import '../data/billing_repository.dart';
import '../domain/billing_models.dart';
import 'billing_format.dart';
import 'billing_providers.dart';

/// Detalhe de uma fatura (com pagamentos e estornos). `autoDispose`: reabrir
/// traz o dado do servidor.
final invoiceDetailProvider =
    FutureProvider.autoDispose.family<Invoice, String>((ref, id) {
  return ref.watch(billingRepositoryProvider).invoice(id);
});

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}

/// "Dar baixa": confirma e registra o recebimento integral da fatura.
Future<void> recordPaymentFlow(
  BuildContext context,
  WidgetRef ref,
  Invoice invoice,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final done = await showDialog<bool>(
    context: context,
    builder: (_) => _PayDialog(invoice: invoice),
  );
  if (done == true) {
    refreshBilling(ref);
    ref.invalidate(invoiceDetailProvider(invoice.id));
    messenger.showSnackBar(SnackBar(content: Text(l10n.payDone)));
  }
}

class _PayDialog extends ConsumerStatefulWidget {
  const _PayDialog({required this.invoice});

  final Invoice invoice;

  @override
  ConsumerState<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends ConsumerState<_PayDialog> {
  // Uma chave por abertura do diálogo: tentar de novo depois de uma queda de
  // rede reenvia a mesma e o servidor não duplica a baixa.
  final _key = const Uuid().v4();
  final _note = TextEditingController();
  late final DateTime _today = _dayOf(DateTime.now());
  late DateTime? _paidOn = _today;
  bool _loading = false;
  String? _error;

  static DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(billingRepositoryProvider).recordPayment(
            widget.invoice.id,
            idempotencyKey: _key,
            // Hoje = "agora" (o servidor usa o relógio dele, sem divergir do
            // fuso da organização).
            paidOn: _paidOn == _today ? null : _paidOn,
            note: _note.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = describeApiError(context, error);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final invoice = widget.invoice;

    return AlertDialog(
      title: Text(l10n.payDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.payDialogBody(
                moneyText(context, invoice.amountCents,
                    currency: invoice.currency,),
                invoice.customer.name,
              ),
            ),
            const SizedBox(height: LySpace.x3),
            LyDateField(
              label: l10n.payDateLabel,
              value: _paidOn,
              onChanged: (d) => setState(() => _paidOn = d ?? _today),
              emptyLabel: l10n.payDateToday,
              clearLabel: l10n.payDateToday,
              firstDate: DateTime(_today.year - 1),
              lastDate: _today,
            ),
            const SizedBox(height: LySpace.x3),
            LyTextField(
              key: const Key('pay_note'),
              label: l10n.payNoteLabel,
              controller: _note,
              maxLength: 500,
            ),
            if (_error != null) ...[
              const SizedBox(height: LySpace.x2),
              Text(_error!, style: LyType.bodySm(c.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          key: const Key('pay_confirm'),
          onPressed: _loading ? null : _confirm,
          child: Text(l10n.payConfirm),
        ),
      ],
    );
  }
}

/// "Estornar": pede o motivo (obrigatório) e desfaz a baixa vigente; a fatura
/// volta a vencida/em aberto. Só owner.
Future<void> reversePaymentFlow(
  BuildContext context,
  WidgetRef ref,
  Invoice invoice,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  Invoice detail = invoice;
  try {
    // A lista não traz os pagamentos: precisa do id da baixa que vale.
    if (invoice.payments.isEmpty) {
      detail = await ref.read(billingRepositoryProvider).invoice(invoice.id);
    }
  } catch (error) {
    if (context.mounted) _snack(context, describeApiError(context, error));
    return;
  }
  final payment = detail.standingPayment;
  if (payment == null || !context.mounted) return;

  final done = await showDialog<bool>(
    context: context,
    builder: (_) => _ReverseDialog(invoice: detail, payment: payment),
  );
  if (done == true) {
    refreshBilling(ref);
    ref.invalidate(invoiceDetailProvider(invoice.id));
    messenger.showSnackBar(SnackBar(content: Text(l10n.reverseDone)));
  }
}

class _ReverseDialog extends ConsumerStatefulWidget {
  const _ReverseDialog({required this.invoice, required this.payment});

  final Invoice invoice;
  final Payment payment;

  @override
  ConsumerState<_ReverseDialog> createState() => _ReverseDialogState();
}

class _ReverseDialogState extends ConsumerState<_ReverseDialog> {
  final _reason = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(billingRepositoryProvider)
          .reversePayment(widget.payment.id, note: _reason.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = describeApiError(context, error);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final invoice = widget.invoice;

    return AlertDialog(
      title: Text(l10n.reverseDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.reverseDialogBody(
                moneyText(context, widget.payment.amountCents,
                    currency: invoice.currency,),
                invoice.customer.name,
              ),
            ),
            const SizedBox(height: LySpace.x3),
            LyTextField(
              key: const Key('reverse_reason'),
              label: l10n.reverseReasonLabel,
              controller: _reason,
              maxLength: 500,
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) ...[
              const SizedBox(height: LySpace.x2),
              Text(_error!, style: LyType.bodySm(c.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          key: const Key('reverse_confirm'),
          onPressed: _loading || _reason.text.trim().isEmpty ? null : _confirm,
          child: Text(
            l10n.reverseConfirm,
            style: TextStyle(color: c.danger),
          ),
        ),
      ],
    );
  }
}

/// Folha com o detalhe da fatura: titular, valores, pagamentos e estornos, e
/// as ações que o papel permite.
Future<void> showInvoiceDetail(
  BuildContext context,
  String invoiceId,
  BillingAccess access,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => InvoiceDetailSheet(invoiceId: invoiceId, access: access),
  );
}

class InvoiceDetailSheet extends ConsumerWidget {
  const InvoiceDetailSheet({
    required this.invoiceId,
    required this.access,
    super.key,
  });

  final String invoiceId;
  final BillingAccess access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final detail = ref.watch(invoiceDetailProvider(invoiceId));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(LySpace.x4),
        child: detail.when(
          loading: () => const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(describeApiError(context, error)),
              TextButton(
                onPressed: () =>
                    ref.invalidate(invoiceDetailProvider(invoiceId)),
                child: Text(l10n.commonRetry),
              ),
            ],
          ),
          data: (invoice) => SingleChildScrollView(
            child: Column(
              key: const Key('invoice_detail'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.invoiceDetailTitle(
                          periodText(context, invoice.period),
                        ),
                        style: LyType.title(c.textPrimary),
                      ),
                    ),
                    InvoiceStatusChip(status: invoice.status),
                  ],
                ),
                const SizedBox(height: LySpace.x2),
                Text(
                  invoice.customer.name,
                  style: LyType.label(c.textPrimary),
                ),
                if (invoice.customer.email.isNotEmpty)
                  Text(
                    invoice.customer.email,
                    style: LyType.caption(c.textSecondary),
                  ),
                if (invoice.customer.accountDeleted)
                  Text(
                    l10n.invoiceAccountDeleted,
                    style: LyType.caption(c.warning),
                  ),
                const SizedBox(height: LySpace.x3),
                Text(
                  moneyText(context, invoice.amountCents,
                      currency: invoice.currency,),
                  style: LyType.numeric(c.textPrimary, size: 28),
                ),
                Text(
                  l10n.invoiceDueOn(dayText(context, invoice.dueDate)),
                  style: LyType.body(c.textSecondary),
                ),
                const SizedBox(height: LySpace.x4),
                Text(
                  l10n.invoicePaymentsTitle,
                  style: LyType.label(c.textSecondary),
                ),
                const SizedBox(height: LySpace.x2),
                if (invoice.payments.isEmpty)
                  Text(
                    l10n.invoicePaymentsEmpty,
                    style: LyType.body(c.textSecondary),
                  ),
                for (final p in invoice.payments)
                  _PaymentTile(payment: p, currency: invoice.currency),
                const SizedBox(height: LySpace.x4),
                if (access.canOperate && invoice.isPayable)
                  LyButton(
                    key: const Key('invoice_detail_pay'),
                    label: l10n.invoiceActionPay,
                    onPressed: () => recordPaymentFlow(context, ref, invoice),
                  ),
                if (access.isOwner && invoice.isPaid)
                  LyButton(
                    key: const Key('invoice_detail_reverse'),
                    label: l10n.invoiceActionReverse,
                    variant: LyButtonVariant.secondary,
                    onPressed: () => reversePaymentFlow(context, ref, invoice),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.payment, required this.currency});

  final Payment payment;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final label = payment.isReversal
        ? l10n.invoicePaymentReversal
        : payment.reversedBy != null
            ? l10n.invoicePaymentReversed
            : l10n.invoicePaymentManual;
    final note = payment.note;

    return Padding(
      padding: const EdgeInsets.only(bottom: LySpace.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label · ${dateTimeText(context, payment.paidAt)}',
                  style: LyType.body(
                    payment.isReversal ? c.danger : c.textPrimary,
                  ),
                ),
                if (note != null && note.isNotEmpty)
                  Text(note, style: LyType.caption(c.textSecondary)),
              ],
            ),
          ),
          Text(
            moneyText(context, payment.amountCents, currency: currency),
            style: LyType.body(c.textPrimary),
          ),
        ],
      ),
    );
  }
}
