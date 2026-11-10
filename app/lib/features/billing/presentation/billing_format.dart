import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/money/money.dart';

String _locale(BuildContext context) =>
    Localizations.localeOf(context).toString();

/// Valor em centavos como moeda no idioma da tela.
String moneyText(BuildContext context, int cents, {String currency = 'BRL'}) =>
    formatCents(cents, _locale(context), currency: currency);

/// Dia civil por extenso curto no idioma da tela (`dd/MM/yyyy`, `MM/dd/yyyy`).
String dayText(BuildContext context, DateTime day) =>
    DateFormat.yMd(_locale(context)).format(day);

/// Instante local como data.
String dateTimeText(BuildContext context, DateTime at) =>
    DateFormat.yMd(_locale(context)).add_Hm().format(at);

/// `AAAA-MM` como "novembro de 2026".
String periodText(BuildContext context, String period) {
  final year = int.tryParse(period.substring(0, 4));
  final month = int.tryParse(period.substring(5, 7));
  if (year == null || month == null) return period;
  return DateFormat.yMMMM(_locale(context)).format(DateTime(year, month));
}

String invoiceStatusLabel(AppLocalizations l10n, String status) {
  return switch (status) {
    'open' => l10n.invoiceStatusOpen,
    'overdue' => l10n.invoiceStatusOverdue,
    'paid' => l10n.invoiceStatusPaid,
    _ => l10n.invoiceStatusCanceled,
  };
}

Color invoiceStatusColor(LyColors c, String status) {
  return switch (status) {
    'open' => c.info,
    'overdue' => c.danger,
    'paid' => c.success,
    _ => c.textSecondary,
  };
}

String subscriptionStatusLabel(AppLocalizations l10n, String status) {
  return switch (status) {
    'active' => l10n.subscriptionStatusActive,
    'paused' => l10n.subscriptionStatusPaused,
    _ => l10n.subscriptionStatusCanceled,
  };
}

/// Etiqueta de status da fatura (texto colorido, sem depender só da cor).
class InvoiceStatusChip extends StatelessWidget {
  const InvoiceStatusChip({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final color = invoiceStatusColor(c, status);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LySpace.x2,
        vertical: LySpace.x1,
      ),
      decoration: BoxDecoration(
        borderRadius: LyRadius.pill,
        border: Border.all(color: color),
      ),
      child: Text(
        invoiceStatusLabel(AppLocalizations.of(context), status),
        style: LyType.caption(color),
      ),
    );
  }
}

/// Selo "inadimplente" (lista de alunos e ficha).
class DelinquentChip extends StatelessWidget {
  const DelinquentChip({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    return Container(
      key: const Key('delinquent_badge'),
      padding: const EdgeInsets.symmetric(
        horizontal: LySpace.x2,
        vertical: LySpace.x1,
      ),
      decoration: BoxDecoration(
        borderRadius: LyRadius.pill,
        border: Border.all(color: c.danger),
      ),
      child: Text(
        AppLocalizations.of(context).billingDelinquent,
        style: LyType.caption(c.danger),
      ),
    );
  }
}
