import 'package:dio/dio.dart';
import 'package:lyfta/features/billing/data/billing_repository.dart';
import 'package:lyfta/features/billing/domain/billing_models.dart';

/// `billing` em memória para os testes de widget: guarda o que o app mandou e
/// devolve o que o teste configurou. Sem rede.
class FakeBillingRepository extends BillingRepository {
  FakeBillingRepository({
    List<BillingPlan>? plans,
    List<Subscription>? subscriptions,
    List<Invoice>? invoices,
    Map<String, String>? statuses,
  })  : plansData = plans ?? [],
        subscriptionsData = subscriptions ?? [],
        invoicesData = invoices ?? [],
        statusesData = statuses ?? {},
        super(Dio());

  final List<BillingPlan> plansData;
  final List<Subscription> subscriptionsData;
  final List<Invoice> invoicesData;
  final Map<String, String> statusesData;

  /// Baixas recebidas: (fatura, chave de idempotência, dia, observação).
  final payments = <(String, String, DateTime?, String?)>[];
  final reversals = <(String, String)>[];
  final createdSubscriptions = <Map<String, Object?>>[];
  final transitions = <(String, String)>[];
  final createdPlans = <(String, int)>[];
  final archivedPlans = <String>[];
  final invoiceQueries = <Map<String, String?>>[];
  final statusCalls = <List<String>>[];
  Object? statusError;

  @override
  Future<List<BillingPlan>> plans({bool activeOnly = false}) async => [
        for (final p in plansData)
          if (!activeOnly || p.active) p,
      ];

  @override
  Future<BillingPlan> createPlan({
    required String name,
    required int amountCents,
  }) async {
    createdPlans.add((name, amountCents));
    final plan = BillingPlan(
      id: 'plan-${plansData.length + 1}',
      name: name,
      amountCents: amountCents,
      currency: 'BRL',
      active: true,
    );
    plansData.add(plan);
    return plan;
  }

  @override
  Future<BillingPlan> archivePlan(String id) async {
    archivedPlans.add(id);
    final i = plansData.indexWhere((p) => p.id == id);
    final old = plansData[i];
    plansData[i] = BillingPlan(
      id: old.id,
      name: old.name,
      amountCents: old.amountCents,
      currency: old.currency,
      active: false,
    );
    return plansData[i];
  }

  @override
  Future<List<Subscription>> subscriptions({String? studentId}) async => [
        for (final s in subscriptionsData)
          if (studentId == null || s.studentId == studentId) s,
      ];

  @override
  Future<Subscription> createSubscription({
    required String studentId,
    required String planId,
    int? amountCents,
    required int dueDay,
    required DateTime startsOn,
  }) async {
    createdSubscriptions.add({
      'student': studentId,
      'plan': planId,
      'amount': amountCents,
      'dueDay': dueDay,
      'startsOn': formatCivilDay(startsOn),
    });
    final plan = plansData.firstWhere((p) => p.id == planId);
    final sub = Subscription(
      id: 'sub-${subscriptionsData.length + 1}',
      studentId: studentId,
      billingPlanId: planId,
      amountCents: amountCents ?? plan.amountCents,
      currency: 'BRL',
      dueDay: dueDay,
      startsOn: startsOn,
      status: 'active',
      customer: const BillingCustomer(name: 'Ana Alves', email: 'ana@x.com'),
    );
    subscriptionsData.add(sub);
    return sub;
  }

  @override
  Future<Subscription> transitionSubscription(String id, String action) async {
    transitions.add((id, action));
    final i = subscriptionsData.indexWhere((s) => s.id == id);
    final old = subscriptionsData[i];
    subscriptionsData[i] = Subscription(
      id: old.id,
      studentId: old.studentId,
      billingPlanId: old.billingPlanId,
      amountCents: old.amountCents,
      currency: old.currency,
      dueDay: old.dueDay,
      startsOn: old.startsOn,
      status: switch (action) {
        'pause' => 'paused',
        'resume' => 'active',
        _ => 'canceled',
      },
      customer: old.customer,
    );
    return subscriptionsData[i];
  }

  @override
  Future<InvoicePage> invoices({
    String? status,
    String? period,
    String? studentId,
    String? cursor,
    int limit = 50,
  }) async {
    invoiceQueries.add({
      'status': status,
      'period': period,
      'student': studentId,
      'cursor': cursor,
    });
    return InvoicePage(
      items: [
        for (final i in invoicesData)
          if ((status == null || i.status == status) &&
              (period == null || i.period == period) &&
              (studentId == null || i.studentId == studentId))
            i,
      ],
    );
  }

  @override
  Future<Invoice> invoice(String id) async =>
      invoicesData.firstWhere((i) => i.id == id);

  /// Troca a fatura guardada por uma com outro status (e pagamentos).
  void _replace(Invoice old, String status, List<Payment> payments) {
    final i = invoicesData.indexWhere((x) => x.id == old.id);
    invoicesData[i] = Invoice(
      id: old.id,
      studentId: old.studentId,
      period: old.period,
      dueDate: old.dueDate,
      amountCents: old.amountCents,
      currency: old.currency,
      status: status,
      paidAt: status == 'paid' ? DateTime.now() : null,
      customer: old.customer,
      payments: payments,
    );
  }

  @override
  Future<Invoice> recordPayment(
    String invoiceId, {
    required String idempotencyKey,
    DateTime? paidOn,
    String? note,
  }) async {
    payments.add((invoiceId, idempotencyKey, paidOn, note));
    final old = invoicesData.firstWhere((i) => i.id == invoiceId);
    _replace(old, 'paid', [
      Payment(
        id: 'pay-$invoiceId',
        amountCents: old.amountCents,
        paidAt: DateTime.now(),
        note: note,
      ),
    ]);
    return invoicesData.firstWhere((i) => i.id == invoiceId);
  }

  @override
  Future<Invoice> reversePayment(
    String paymentId, {
    required String note,
  }) async {
    reversals.add((paymentId, note));
    final old = invoicesData.firstWhere(
      (i) => i.payments.any((p) => p.id == paymentId),
    );
    _replace(old, 'overdue', [
      for (final p in old.payments)
        Payment(
          id: p.id,
          amountCents: p.amountCents,
          paidAt: p.paidAt,
          reversedBy: 'rev-1',
        ),
      Payment(
        id: 'rev-1',
        amountCents: old.amountCents,
        paidAt: DateTime.now(),
        note: note,
        reversalOf: paymentId,
      ),
    ]);
    return invoicesData.firstWhere((i) => i.id == old.id);
  }

  @override
  Future<Map<String, String>> studentStatuses(List<String> ids) async {
    statusCalls.add(ids);
    if (statusError != null) throw statusError!;
    return {
      for (final id in ids)
        if (statusesData.containsKey(id)) id: statusesData[id]!,
    };
  }

  @override
  Future<InvoicePage> myInvoices({String? cursor, int limit = 50}) async =>
      InvoicePage(items: invoicesData);
}

Invoice testInvoice({
  required String id,
  String studentId = 'aluno-1',
  String name = 'Ana Alves',
  String period = '2026-11',
  DateTime? dueDate,
  int amountCents = 12000,
  String status = 'open',
  bool accountDeleted = false,
}) {
  return Invoice(
    id: id,
    studentId: studentId,
    period: period,
    dueDate: dueDate ?? DateTime(2026, 11, 10),
    amountCents: amountCents,
    currency: 'BRL',
    status: status,
    customer: BillingCustomer(
      name: name,
      email: '${name.toLowerCase().replaceAll(' ', '.')}@example.com',
      accountDeleted: accountDeleted,
    ),
  );
}
