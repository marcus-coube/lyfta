import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/ly_date_field.dart';
import '../../../shared/widgets/ly_error_state.dart';
import '../../../shared/widgets/ly_money_field.dart';
import '../../../shared/widgets/ly_skeleton.dart';
import '../data/billing_repository.dart';
import '../domain/billing_models.dart';
import 'billing_format.dart';
import 'billing_providers.dart';
import 'invoice_widgets.dart';

/// Aba Financeiro da ficha do aluno (owner e coach `own_students`): a
/// assinatura vigente com suas ações e o histórico de faturas e pagamentos.
class StudentBillingTab extends ConsumerWidget {
  const StudentBillingTab({
    required this.studentId,
    required this.studentName,
    super.key,
  });

  final String studentId;
  final String studentName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final access = ref.watch(billingAccessProvider);
    final subs = ref.watch(studentSubscriptionsProvider(studentId));
    final query = InvoiceQuery(studentId: studentId);
    final invoices = ref.watch(invoiceListProvider(query));

    if (subs.isLoading && !subs.hasValue) {
      return const Padding(
        padding: EdgeInsets.all(LySpace.x4),
        child: Column(
          children: [
            LySkeletonListTile(),
            SizedBox(height: LySpace.x3),
            LySkeletonListTile(),
          ],
        ),
      );
    }
    if (subs.hasError && !subs.hasValue) {
      final error = subs.error!;
      return LyErrorState(
        message: describeApiError(context, error),
        retryable: isRetryableError(error),
        onRetry: () => ref.invalidate(studentSubscriptionsProvider(studentId)),
      );
    }

    final all = subs.valueOrNull ?? const <Subscription>[];
    final live = all.where((s) => s.isLive).firstOrNull;

    return ListView(
      padding: const EdgeInsets.all(LySpace.x4),
      children: [
        Text(l10n.subscriptionTitle, style: LyType.label(c.textSecondary)),
        const SizedBox(height: LySpace.x2),
        _SubscriptionCard(
          studentId: studentId,
          studentName: studentName,
          subscription: live,
        ),
        const SizedBox(height: LySpace.x6),
        Text(l10n.studentInvoicesTitle, style: LyType.label(c.textSecondary)),
        ...invoices.when(
          loading: () => const [
            SizedBox(height: LySpace.x3),
            LySkeletonListTile(),
          ],
          error: (error, _) => [
            SizedBox(
              height: 200,
              child: LyErrorState(
                message: describeApiError(context, error),
                retryable: isRetryableError(error),
                onRetry: () => ref.invalidate(invoiceListProvider(query)),
              ),
            ),
          ],
          data: (state) => [
            if (state.items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: LySpace.x3),
                child: Text(
                  l10n.studentInvoicesEmpty,
                  style: LyType.body(c.textSecondary),
                ),
              ),
            for (final invoice in state.items)
              Padding(
                padding: const EdgeInsets.only(top: LySpace.x2),
                child: InvoiceTile(
                  invoice: invoice,
                  access: access,
                  showCustomer: false,
                ),
              ),
            if (state.hasMore)
              InvoiceLoadMoreFooter(query: query, state: state),
          ],
        ),
      ],
    );
  }
}

class _SubscriptionCard extends ConsumerStatefulWidget {
  const _SubscriptionCard({
    required this.studentId,
    required this.studentName,
    required this.subscription,
  });

  final String studentId;
  final String studentName;
  final Subscription? subscription;

  @override
  ConsumerState<_SubscriptionCard> createState() => _SubscriptionCardState();
}

class _SubscriptionCardState extends ConsumerState<_SubscriptionCard> {
  bool _busy = false;

  Future<void> _openDialog(Subscription? existing) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => SubscriptionDialog(
        studentId: widget.studentId,
        existing: existing,
      ),
    );
    if (saved == true) {
      refreshBilling(ref);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            existing == null
                ? l10n.subscriptionCreated
                : l10n.subscriptionUpdated,
          ),
        ),
      );
    }
  }

  Future<void> _transition(Subscription sub, String action) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (action == 'cancel') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.subscriptionCancelTitle(widget.studentName)),
          content: Text(l10n.subscriptionCancelBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              key: const Key('subscription_cancel_confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                l10n.subscriptionCancel,
                style: TextStyle(color: context.ly.danger),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(billingRepositoryProvider)
          .transitionSubscription(sub.id, action);
      refreshBilling(ref);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            switch (action) {
              'pause' => l10n.subscriptionPaused,
              'resume' => l10n.subscriptionResumed,
              _ => l10n.subscriptionCanceled,
            },
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(describeApiError(context, error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final sub = widget.subscription;

    if (sub == null) {
      return LyCard(
        padding: const EdgeInsets.all(LySpace.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.subscriptionNone, style: LyType.body(c.textSecondary)),
            const SizedBox(height: LySpace.x3),
            LyButton(
              key: const Key('subscription_create'),
              label: l10n.subscriptionCreate,
              expanded: false,
              onPressed: _busy ? null : () => _openDialog(null),
            ),
          ],
        ),
      );
    }

    return LyCard(
      key: const Key('subscription_card'),
      padding: const EdgeInsets.all(LySpace.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  moneyText(context, sub.amountCents, currency: sub.currency),
                  style: LyType.numeric(c.textPrimary, size: 24),
                ),
              ),
              Text(
                subscriptionStatusLabel(l10n, sub.status),
                key: const Key('subscription_status'),
                style: LyType.label(sub.isActive ? c.success : c.warning),
              ),
            ],
          ),
          const SizedBox(height: LySpace.x1),
          Text(
            l10n.subscriptionSummary(sub.dueDay),
            style: LyType.body(c.textSecondary),
          ),
          Text(
            l10n.subscriptionStartsOn(dayText(context, sub.startsOn)),
            style: LyType.caption(c.textSecondary),
          ),
          const SizedBox(height: LySpace.x3),
          Wrap(
            spacing: LySpace.x2,
            runSpacing: LySpace.x2,
            children: [
              LyButton(
                key: const Key('subscription_edit'),
                label: l10n.subscriptionEdit,
                variant: LyButtonVariant.secondary,
                expanded: false,
                onPressed: _busy ? null : () => _openDialog(sub),
              ),
              if (sub.isActive)
                LyButton(
                  key: const Key('subscription_pause'),
                  label: l10n.subscriptionPause,
                  variant: LyButtonVariant.secondary,
                  expanded: false,
                  onPressed: _busy ? null : () => _transition(sub, 'pause'),
                ),
              if (sub.isPaused)
                LyButton(
                  key: const Key('subscription_resume'),
                  label: l10n.subscriptionResume,
                  variant: LyButtonVariant.secondary,
                  expanded: false,
                  onPressed: _busy ? null : () => _transition(sub, 'resume'),
                ),
              LyButton(
                key: const Key('subscription_cancel'),
                label: l10n.subscriptionCancel,
                variant: LyButtonVariant.ghost,
                expanded: false,
                onPressed: _busy ? null : () => _transition(sub, 'cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Criar (plano, valor, vencimento, início) ou editar (valor e vencimento,
/// que valem a partir da próxima fatura) a assinatura. Fecha com `true` ao
/// salvar.
class SubscriptionDialog extends ConsumerStatefulWidget {
  const SubscriptionDialog({
    required this.studentId,
    this.existing,
    super.key,
  });

  final String studentId;
  final Subscription? existing;

  @override
  ConsumerState<SubscriptionDialog> createState() => _SubscriptionDialogState();
}

class _SubscriptionDialogState extends ConsumerState<SubscriptionDialog> {
  late final DateTime _today = () {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }();
  BillingPlan? _plan;
  late int? _cents = widget.existing?.amountCents;
  late int _dueDay = widget.existing?.dueDay ?? _today.day.clamp(1, 28);
  late DateTime _startsOn = _today;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.existing != null;

  bool get _valid => (_cents ?? 0) > 0 && (_editing || _plan != null);

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = ref.read(billingRepositoryProvider);
      final existing = widget.existing;
      if (existing == null) {
        final plan = _plan!;
        await repository.createSubscription(
          studentId: widget.studentId,
          planId: plan.id,
          // Sem valor próprio, o servidor usa o do plano.
          amountCents: _cents == plan.amountCents ? null : _cents,
          dueDay: _dueDay,
          startsOn: _startsOn,
        );
      } else {
        await repository.patchSubscription(
          existing.id,
          amountCents: _cents == existing.amountCents ? null : _cents,
          dueDay: _dueDay == existing.dueDay ? null : _dueDay,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = describeApiError(context, error);
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final plans = _editing ? null : ref.watch(activeBillingPlansProvider);
    final planList = plans?.valueOrNull ?? const <BillingPlan>[];

    return AlertDialog(
      title: Text(
        _editing ? l10n.subscriptionEdit : l10n.subscriptionCreate,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_editing) ...[
              if (plans != null && plans.isLoading)
                const Center(child: CircularProgressIndicator())
              else if (plans != null && plans.hasError)
                Text(
                  describeApiError(context, plans.error!),
                  style: LyType.bodySm(c.danger),
                )
              else if (planList.isEmpty)
                Text(
                  ref.watch(billingAccessProvider).isOwner
                      ? l10n.subscriptionNoPlansOwner
                      : l10n.subscriptionNoPlansCoach,
                  key: const Key('subscription_no_plans'),
                  style: LyType.body(c.textSecondary),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.subscriptionPlanLabel,
                      style: LyType.label(c.textPrimary),
                    ),
                    DropdownButton<BillingPlan>(
                      key: const Key('subscription_plan'),
                      value: _plan,
                      isExpanded: true,
                      hint: Text(l10n.subscriptionPlanHint),
                      onChanged: (p) => setState(() {
                        _plan = p;
                        _cents = p?.amountCents;
                      }),
                      items: [
                        for (final p in planList)
                          DropdownMenuItem(
                            value: p,
                            child: Text(
                              '${p.name} · ${moneyText(context, p.amountCents, currency: p.currency)}',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              const SizedBox(height: LySpace.x3),
            ],
            LyMoneyField(
              fieldKey: const Key('subscription_amount'),
              label: l10n.subscriptionAmountLabel,
              cents: _cents,
              onChanged: (v) => setState(() => _cents = v),
            ),
            const SizedBox(height: LySpace.x3),
            Text(
              l10n.subscriptionDueDayLabel,
              style: LyType.label(c.textPrimary),
            ),
            DropdownButton<int>(
              key: const Key('subscription_due_day'),
              value: _dueDay,
              isExpanded: true,
              onChanged: (d) => setState(() => _dueDay = d ?? _dueDay),
              items: [
                for (var d = 1; d <= 28; d++)
                  DropdownMenuItem(value: d, child: Text('$d')),
              ],
            ),
            if (!_editing) ...[
              const SizedBox(height: LySpace.x3),
              LyDateField(
                label: l10n.subscriptionStartsOnLabel,
                value: _startsOn,
                onChanged: (d) => setState(() => _startsOn = d ?? _today),
                emptyLabel: l10n.payDateToday,
                clearLabel: l10n.payDateToday,
                firstDate: DateTime(_today.year - 1),
                lastDate: DateTime(_today.year + 1, 12, 31),
              ),
            ] else ...[
              const SizedBox(height: LySpace.x2),
              Text(
                l10n.subscriptionEditHint,
                style: LyType.caption(c.textSecondary),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: LySpace.x2),
              Text(_error!, style: LyType.bodySm(c.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          key: const Key('subscription_save'),
          onPressed: _saving || !_valid ? null : _save,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
