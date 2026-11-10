// Modelos do financeiro (`billing`, ADR-017). Todo valor monetário é `int`
// em centavos (ADR-007).

/// `yyyy-MM-dd` do servidor como dia civil, sem fuso.
DateTime parseCivilDay(String raw) {
  return DateTime(
    int.parse(raw.substring(0, 4)),
    int.parse(raw.substring(5, 7)),
    int.parse(raw.substring(8, 10)),
  );
}

/// Titular da assinatura: cópia de nome e e-mail guardada no `billing`
/// (ADR-017 §5); `accountDeleted` marca quem excluiu a conta.
class BillingCustomer {
  const BillingCustomer({
    required this.name,
    required this.email,
    this.accountDeleted = false,
  });

  factory BillingCustomer.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const BillingCustomer(name: '', email: '');
    return BillingCustomer(
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      accountDeleted: json['account_deleted'] as bool? ?? false,
    );
  }

  final String name;
  final String email;
  final bool accountDeleted;
}

/// Plano de mensalidade da organização.
class BillingPlan {
  const BillingPlan({
    required this.id,
    required this.name,
    required this.amountCents,
    required this.currency,
    required this.active,
  });

  factory BillingPlan.fromJson(Map<String, dynamic> json) => BillingPlan(
        id: json['id'] as String,
        name: json['name'] as String,
        amountCents: (json['amount_cents'] as num).toInt(),
        currency: json['currency'] as String? ?? 'BRL',
        active: json['active'] as bool? ?? true,
      );

  final String id;
  final String name;
  final int amountCents;
  final String currency;
  final bool active;
}

/// Assinatura do aluno: `active`, `paused` ou `canceled`.
class Subscription {
  const Subscription({
    required this.id,
    required this.studentId,
    required this.billingPlanId,
    required this.amountCents,
    required this.currency,
    required this.dueDay,
    required this.startsOn,
    required this.status,
    required this.customer,
  });

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
        id: json['id'] as String,
        studentId: json['student_id'] as String,
        billingPlanId: json['billing_plan_id'] as String,
        amountCents: (json['amount_cents'] as num).toInt(),
        currency: json['currency'] as String? ?? 'BRL',
        dueDay: (json['due_day'] as num).toInt(),
        startsOn: parseCivilDay(json['starts_on'] as String),
        status: json['status'] as String,
        customer: BillingCustomer.fromJson(
          json['customer'] as Map<String, dynamic>?,
        ),
      );

  final String id;
  final String studentId;
  final String billingPlanId;
  final int amountCents;
  final String currency;
  final int dueDay;
  final DateTime startsOn;
  final String status;
  final BillingCustomer customer;

  bool get isActive => status == 'active';
  bool get isPaused => status == 'paused';
  bool get isCanceled => status == 'canceled';

  /// Ativa ou pausada: a que ocupa a vaga única do aluno.
  bool get isLive => isActive || isPaused;
}

/// Baixa manual ou estorno (um estorno é um pagamento com `reversal_of`).
class Payment {
  const Payment({
    required this.id,
    required this.amountCents,
    required this.paidAt,
    this.note,
    this.reversedBy,
    this.reversalOf,
  });

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
        id: json['id'] as String,
        amountCents: (json['amount_cents'] as num).toInt(),
        paidAt: DateTime.parse(json['paid_at'] as String).toLocal(),
        note: json['note'] as String?,
        reversedBy: json['reversed_by'] as String?,
        reversalOf: json['reversal_of'] as String?,
      );

  final String id;
  final int amountCents;
  final DateTime paidAt;
  final String? note;
  final String? reversedBy;
  final String? reversalOf;

  bool get isReversal => reversalOf != null;

  /// Baixa que ainda vale (nem é estorno, nem foi estornada): a que o estorno
  /// da fatura paga atinge.
  bool get isStanding => reversalOf == null && reversedBy == null;
}

/// Fatura mensal. Na visão do aluno (`/me/invoices`) o servidor omite titular,
/// assinatura e pagamentos.
class Invoice {
  const Invoice({
    required this.id,
    required this.period,
    required this.dueDate,
    required this.amountCents,
    required this.currency,
    required this.status,
    this.studentId = '',
    this.paidAt,
    this.customer = const BillingCustomer(name: '', email: ''),
    this.payments = const [],
  });

  factory Invoice.fromJson(Map<String, dynamic> json) => Invoice(
        id: json['id'] as String,
        studentId: json['student_id'] as String? ?? '',
        period: json['period'] as String,
        dueDate: parseCivilDay(json['due_date'] as String),
        amountCents: (json['amount_cents'] as num).toInt(),
        currency: json['currency'] as String? ?? 'BRL',
        status: json['status'] as String,
        paidAt: json['paid_at'] == null
            ? null
            : DateTime.parse(json['paid_at'] as String).toLocal(),
        customer: BillingCustomer.fromJson(
          json['customer'] as Map<String, dynamic>?,
        ),
        payments: [
          for (final p in json['payments'] as List<dynamic>? ?? const [])
            Payment.fromJson(p as Map<String, dynamic>),
        ],
      );

  final String id;
  final String studentId;

  /// `AAAA-MM`.
  final String period;
  final DateTime dueDate;
  final int amountCents;
  final String currency;

  /// `open`, `overdue`, `paid` ou `canceled`.
  final String status;
  final DateTime? paidAt;
  final BillingCustomer customer;
  final List<Payment> payments;

  bool get isPayable => status == 'open' || status == 'overdue';
  bool get isPaid => status == 'paid';

  /// A baixa que um estorno desfaria, se houver.
  Payment? get standingPayment {
    for (final p in payments) {
      if (p.isStanding) return p;
    }
    return null;
  }
}

class InvoicePage {
  const InvoicePage({required this.items, this.nextCursor});

  final List<Invoice> items;
  final String? nextCursor;
}
