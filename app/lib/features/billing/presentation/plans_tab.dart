import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/ly_error_state.dart';
import '../../../shared/widgets/ly_money_field.dart';
import '../../../shared/widgets/ly_skeleton.dart';
import '../data/billing_repository.dart';
import '../domain/billing_models.dart';
import 'billing_format.dart';
import 'billing_providers.dart';

/// Planos de mensalidade (só owner): criar, editar e arquivar. Plano
/// arquivado some da escolha ao assinar; assinaturas existentes mantêm o valor
/// que copiaram.
class PlansTab extends ConsumerWidget {
  const PlansTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final plans = ref.watch(billingPlansProvider);

    return Scaffold(
      backgroundColor: c.background,
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('plan_new'),
        onPressed: () => _editPlan(context, ref, null),
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        icon: const Icon(Icons.add),
        label: Text(l10n.billingPlanNew),
      ),
      body: plans.when(
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
          onRetry: () => ref.invalidate(billingPlansProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(LySpace.x4),
                child: Text(
                  l10n.billingPlansEmpty,
                  style: LyType.body(c.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final active = items.where((p) => p.active).toList();
          final archived = items.where((p) => !p.active).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              LySpace.x4,
              LySpace.x4,
              LySpace.x4,
              LySpace.x16,
            ),
            children: [
              for (final p in active) _PlanCard(plan: p),
              if (archived.isNotEmpty) ...[
                const SizedBox(height: LySpace.x4),
                Text(
                  l10n.billingPlansArchivedSection,
                  style: LyType.label(c.textSecondary),
                ),
                for (final p in archived) _PlanCard(plan: p),
              ],
            ],
          );
        },
      ),
    );
  }
}

Future<void> _editPlan(
  BuildContext context,
  WidgetRef ref,
  BillingPlan? plan,
) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _PlanDialog(plan: plan),
  );
  if (saved == true) {
    ref.invalidate(billingPlansProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).billingPlanSaved)),
      );
    }
  }
}

Future<void> _archivePlan(
  BuildContext context,
  WidgetRef ref,
  BillingPlan plan,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.billingPlanArchiveTitle(plan.name)),
      content: Text(l10n.billingPlanArchiveBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          key: const Key('plan_archive_confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.billingPlanArchive),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await ref.read(billingRepositoryProvider).archivePlan(plan.id);
    ref.invalidate(billingPlansProvider);
    messenger.showSnackBar(SnackBar(content: Text(l10n.billingPlanArchived)));
  } catch (error) {
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeApiError(context, error))),
      );
    }
  }
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard({required this.plan});

  final BillingPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: LySpace.x2),
      child: LyCard(
        key: Key('plan_${plan.id}'),
        padding: const EdgeInsets.all(LySpace.x4),
        onTap: plan.active ? () => _editPlan(context, ref, plan) : null,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.name,
                    style: LyType.label(
                      plan.active ? c.textPrimary : c.textSecondary,
                    ),
                  ),
                  Text(
                    l10n.billingPlanPerMonth(
                      moneyText(context, plan.amountCents,
                          currency: plan.currency,),
                    ),
                    style: LyType.caption(c.textSecondary),
                  ),
                ],
              ),
            ),
            if (plan.active)
              IconButton(
                key: Key('plan_archive_${plan.id}'),
                tooltip: l10n.billingPlanArchive,
                icon: const Icon(Icons.archive_outlined),
                color: c.textSecondary,
                onPressed: () => _archivePlan(context, ref, plan),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlanDialog extends ConsumerStatefulWidget {
  const _PlanDialog({this.plan});

  final BillingPlan? plan;

  @override
  ConsumerState<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends ConsumerState<_PlanDialog> {
  late final _name = TextEditingController(text: widget.plan?.name ?? '');
  late int? _cents = widget.plan?.amountCents;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty && (_cents ?? 0) > 0;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = ref.read(billingRepositoryProvider);
      final plan = widget.plan;
      if (plan == null) {
        await repository.createPlan(
          name: _name.text.trim(),
          amountCents: _cents!,
        );
      } else {
        await repository.updatePlan(
          plan.id,
          name: _name.text.trim(),
          amountCents: _cents!,
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
    final editing = widget.plan != null;

    return AlertDialog(
      title: Text(editing ? l10n.billingPlanEdit : l10n.billingPlanNew),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LyTextField(
              key: const Key('plan_name'),
              label: l10n.billingPlanNameLabel,
              controller: _name,
              autofocus: true,
              maxLength: 120,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: LySpace.x3),
            LyMoneyField(
              fieldKey: const Key('plan_amount'),
              label: l10n.billingPlanAmountLabel,
              cents: _cents,
              onChanged: (v) => setState(() => _cents = v),
            ),
            if (editing) ...[
              const SizedBox(height: LySpace.x2),
              Text(
                l10n.billingPlanEditHint,
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
          key: const Key('plan_save'),
          onPressed: _saving || !_valid ? null : _save,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
