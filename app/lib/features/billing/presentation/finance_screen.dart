import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/http/api_exception.dart';
import '../../../core/http/api_exception_l10n.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../shared/widgets/ly_error_state.dart';
import '../../../shared/widgets/ly_skeleton.dart';
import '../../account/data/tenant_repository.dart';
import 'billing_format.dart';
import 'billing_providers.dart';
import 'invoice_widgets.dart';
import 'plans_tab.dart';

/// Largura a partir da qual as faturas viram tabela.
const financeTableBreakpoint = 840.0;

/// Filtro de status das faturas (`null` = todas).
final invoiceStatusFilterProvider = StateProvider<String?>((ref) => null);

/// Filtro de mês `AAAA-MM` (`null` = todos).
final invoicePeriodFilterProvider = StateProvider<String?>((ref) => null);

/// Aba Financeiro do shell do professor (P7.4): faturas da organização (do
/// owner) ou dos próprios alunos (coach `own_students`, sem estorno); planos
/// de mensalidade só para o owner.
class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key});

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabs;

  TabController _controller(int length) {
    final current = _tabs;
    if (current != null && current.length == length) return current;
    // O TabBar antigo ainda está na árvore neste build: descarta depois.
    if (current != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => current.dispose());
    }
    return _tabs = TabController(length: length, vsync: this);
  }

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final access = ref.watch(billingAccessProvider);
    final hasPlans = access.isOwner;
    final tabs = _controller(hasPlans ? 2 : 1);

    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          if (hasPlans)
            ColoredBox(
              color: c.surface,
              child: TabBar(
                controller: tabs,
                labelColor: c.accent,
                unselectedLabelColor: c.textSecondary,
                indicatorColor: c.accent,
                tabs: [
                  Tab(text: l10n.billingTabInvoices),
                  Tab(text: l10n.billingTabPlans),
                ],
              ),
            ),
          Expanded(
            child: hasPlans
                ? TabBarView(
                    controller: tabs,
                    children: [
                      InvoicesTab(access: access),
                      const PlansTab(),
                    ],
                  )
                : InvoicesTab(access: access),
          ),
        ],
      ),
    );
  }
}

/// Meses do filtro: os 12 anteriores ao atual, o atual e o próximo.
List<String> _periodOptions(DateTime now) {
  String period(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
  return [
    for (var offset = 1; offset >= -11; offset--)
      period(DateTime(now.year, now.month + offset)),
  ];
}

/// Faturas com filtros de situação e mês; tabela na tela larga.
class InvoicesTab extends ConsumerWidget {
  const InvoicesTab({required this.access, super.key});

  final BillingAccess access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(invoiceStatusFilterProvider);
    final period = ref.watch(invoicePeriodFilterProvider);
    final query = InvoiceQuery(status: status, period: period);
    final invoices = ref.watch(invoiceListProvider(query));
    final filtered = status != null || period != null;

    final header = _Filters(status: status, period: period);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= financeTableBreakpoint;
        return invoices.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(LySpace.x4),
            physics: const NeverScrollableScrollPhysics(),
            children: [
              header,
              for (var i = 0; i < 5; i++) ...[
                const SizedBox(height: LySpace.x3),
                const LySkeletonListTile(),
              ],
            ],
          ),
          error: (error, _) {
            // O owner pode ter desligado o acesso do professor: relê a
            // configuração para a aba sumir em vez de insistir no 403.
            if (error is ApiException &&
                error.code == 'billing_access_denied') {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => ref.invalidate(tenantSettingsProvider),
              );
            }
            return ListView(
              padding: const EdgeInsets.all(LySpace.x4),
              children: [
                header,
                SizedBox(
                  height: 280,
                  child: LyErrorState(
                    message: describeApiError(context, error),
                    retryable: isRetryableError(error),
                    onRetry: () => ref.invalidate(invoiceListProvider(query)),
                  ),
                ),
              ],
            );
          },
          data: (state) {
            if (state.items.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(LySpace.x4),
                children: [
                  header,
                  const SizedBox(height: LySpace.x8),
                  Center(
                    child: Text(
                      filtered
                          ? l10n.invoicesEmptyFiltered
                          : l10n.invoicesEmpty,
                      style: LyType.body(context.ly.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              );
            }
            final lead = wide ? 2 : 1;
            final footer = state.hasMore ? 1 : 0;
            return ListView.builder(
              padding: const EdgeInsets.all(LySpace.x4),
              itemCount: lead + state.items.length + footer,
              itemBuilder: (context, index) {
                if (index == 0) return header;
                if (wide && index == 1) return const InvoiceTableHeader();
                final i = index - lead;
                if (i >= state.items.length) {
                  return InvoiceLoadMoreFooter(query: query, state: state);
                }
                final invoice = state.items[i];
                return Padding(
                  padding: const EdgeInsets.only(top: LySpace.x2),
                  child: wide
                      ? InvoiceTableRow(invoice: invoice, access: access)
                      : InvoiceTile(invoice: invoice, access: access),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _Filters extends ConsumerWidget {
  const _Filters({required this.status, required this.period});

  final String? status;
  final String? period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ly;
    final l10n = AppLocalizations.of(context);
    final months = _periodOptions(DateTime.now());
    // O mês escolhido continua na lista mesmo se for antigo demais.
    final options = [
      ...months,
      if (period != null && !months.contains(period)) period!,
    ];

    return Wrap(
      spacing: LySpace.x2,
      runSpacing: LySpace.x2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final s in const [null, 'open', 'overdue', 'paid', 'canceled'])
          ChoiceChip(
            key: Key('invoices_filter_${s ?? 'all'}'),
            label: Text(
              s == null ? l10n.invoicesFilterAll : invoiceStatusLabel(l10n, s),
            ),
            selected: status == s,
            onSelected: (_) =>
                ref.read(invoiceStatusFilterProvider.notifier).state = s,
          ),
        DropdownButton<String?>(
          key: const Key('invoices_filter_period'),
          value: period,
          underline: const SizedBox.shrink(),
          style: LyType.body(c.textPrimary),
          onChanged: (value) =>
              ref.read(invoicePeriodFilterProvider.notifier).state = value,
          items: [
            DropdownMenuItem<String?>(
              child: Text(l10n.invoicesPeriodAll),
            ),
            for (final p in options)
              DropdownMenuItem<String?>(
                value: p,
                child: Text(periodText(context, p)),
              ),
          ],
        ),
      ],
    );
  }
}
