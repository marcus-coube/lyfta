import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/auth_state.dart';
import '../../account/data/tenant_repository.dart';
import '../data/billing_repository.dart';
import '../domain/billing_models.dart';

/// O que o usuário logado pode fazer no financeiro (ADR-017 §3).
enum BillingAccess {
  /// Aluno, ou ainda sem a configuração da organização: nada de financeiro.
  none,

  /// Coach com `status_only`: só o selo "inadimplente", sem valores.
  statusOnly,

  /// Coach com `own_students`: assinaturas e faturas dos próprios alunos e
  /// baixa manual; sem planos, estorno nem receita.
  coachOperator,

  /// Owner: tudo.
  owner;

  /// Vê valores e opera (aba Financeiro, aba da ficha).
  bool get canOperate => this == coachOperator || this == owner;

  bool get isOwner => this == owner;
}

/// Acesso do usuário ao financeiro. O owner não depende de rede; o coach
/// depende de `coach_billing_access` da organização (`GET /v1/tenant`, que
/// todo papel lê). Enquanto a configuração carrega, o coach não tem aba.
final billingAccessProvider = Provider<BillingAccess>((ref) {
  final auth = ref.watch(authControllerProvider);
  if (!auth.roles.contains(UserRole.coach)) return BillingAccess.none;
  if (auth.isOwner) return BillingAccess.owner;
  final tenant = ref.watch(tenantSettingsProvider).valueOrNull;
  if (tenant == null) return BillingAccess.none;
  return tenant.coachBillingAccess == 'own_students'
      ? BillingAccess.coachOperator
      : BillingAccess.statusOnly;
});

/// Sobe a cada mudança no financeiro (baixa, estorno, assinatura): quem exibe
/// o selo "inadimplente" (lista e ficha) recarrega.
final billingVersionProvider = StateProvider<int>((ref) => 0);

/// Selo do aluno: `ok`, `delinquent` ou `none`. `null` quando o `billing` não
/// respondeu — o selo some, a tela não quebra.
final studentBillingStatusProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, studentId) async {
  ref.watch(billingVersionProvider);
  try {
    final map =
        await ref.watch(billingRepositoryProvider).studentStatuses([studentId]);
    return map[studentId];
  } catch (_) {
    return null;
  }
});

/// Planos de mensalidade (todos, ativos e arquivados).
final billingPlansProvider =
    FutureProvider.autoDispose<List<BillingPlan>>((ref) {
  return ref.watch(billingRepositoryProvider).plans();
});

/// Planos que ainda aceitam assinatura (a escolha ao assinar um aluno). Owner e
/// coach `own_students` leem.
final activeBillingPlansProvider =
    FutureProvider.autoDispose<List<BillingPlan>>((ref) {
  return ref.watch(billingRepositoryProvider).plans(activeOnly: true);
});

/// Recorte de faturas: do aluno (ficha), da organização (aba Financeiro) ou
/// as próprias (`mine`, visão do aluno).
class InvoiceQuery {
  const InvoiceQuery(
      {this.studentId, this.status, this.period, this.mine = false,});

  final String? studentId;
  final String? status;

  /// `AAAA-MM`.
  final String? period;
  final bool mine;

  @override
  bool operator ==(Object other) =>
      other is InvoiceQuery &&
      other.studentId == studentId &&
      other.status == status &&
      other.period == period &&
      other.mine == mine;

  @override
  int get hashCode => Object.hash(studentId, status, period, mine);
}

class InvoiceListState {
  const InvoiceListState({
    required this.items,
    this.nextCursor,
    this.loadingMore = false,
    this.loadMoreFailed = false,
  });

  final List<Invoice> items;
  final String? nextCursor;
  final bool loadingMore;
  final bool loadMoreFailed;

  bool get hasMore => nextCursor != null;

  InvoiceListState copyWith({
    List<Invoice>? items,
    String? nextCursor,
    bool clearCursor = false,
    bool? loadingMore,
    bool? loadMoreFailed,
  }) =>
      InvoiceListState(
        items: items ?? this.items,
        nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
        loadingMore: loadingMore ?? this.loadingMore,
        loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
      );
}

/// Lista de faturas paginada pelo cursor do servidor.
class InvoiceListController
    extends AutoDisposeFamilyAsyncNotifier<InvoiceListState, InvoiceQuery> {
  static const int pageSize = 30;

  int _generation = 0;

  Future<InvoicePage> _fetch(String? cursor) {
    final repository = ref.read(billingRepositoryProvider);
    if (arg.mine) return repository.myInvoices(cursor: cursor, limit: pageSize);
    return repository.invoices(
      status: arg.status,
      period: arg.period,
      studentId: arg.studentId,
      cursor: cursor,
      limit: pageSize,
    );
  }

  @override
  Future<InvoiceListState> build(InvoiceQuery arg) async {
    _generation++;
    final page = await _fetch(null);
    return InvoiceListState(items: page.items, nextCursor: page.nextCursor);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final generation = _generation;
    state =
        AsyncData(current.copyWith(loadingMore: true, loadMoreFailed: false));
    try {
      final page = await _fetch(current.nextCursor);
      if (generation != _generation) return;
      state = AsyncData(
        InvoiceListState(
          items: [...current.items, ...page.items],
          nextCursor: page.nextCursor,
        ),
      );
    } catch (_) {
      if (generation != _generation) return;
      state = AsyncData(
        current.copyWith(loadingMore: false, loadMoreFailed: true),
      );
    }
  }

  void refresh() => ref.invalidateSelf();
}

final invoiceListProvider = AsyncNotifierProvider.autoDispose
    .family<InvoiceListController, InvoiceListState, InvoiceQuery>(
  InvoiceListController.new,
);

/// Assinaturas do aluno (a ficha mostra a vigente e o histórico).
final studentSubscriptionsProvider = FutureProvider.autoDispose
    .family<List<Subscription>, String>((ref, studentId) {
  return ref
      .watch(billingRepositoryProvider)
      .subscriptions(studentId: studentId);
});

/// Atualiza tudo que o financeiro exibe depois de uma mudança.
void refreshBilling(WidgetRef ref) {
  ref.invalidate(invoiceListProvider);
  ref.invalidate(studentSubscriptionsProvider);
  ref.read(billingVersionProvider.notifier).state++;
}
