import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/http/api_exception.dart';
import '../../../core/http/providers.dart';
import '../domain/billing_models.dart';

/// Financeiro sobre o `billing` (`/v1/billing/*`, `/v1/me/invoices`).
class BillingRepository {
  BillingRepository(this._dio);

  final Dio _dio;

  // ---- Planos de mensalidade ----

  Future<List<BillingPlan>> plans({bool activeOnly = false}) => _call(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/v1/billing/plans',
          queryParameters: {if (activeOnly) 'active': 'true'},
        );
        return [
          for (final raw in response.data!['items'] as List<dynamic>? ?? [])
            BillingPlan.fromJson(raw as Map<String, dynamic>),
        ];
      });

  Future<BillingPlan> createPlan({
    required String name,
    required int amountCents,
  }) =>
      _call(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/v1/billing/plans',
          data: {'name': name, 'amount_cents': amountCents},
        );
        return BillingPlan.fromJson(response.data!);
      });

  Future<BillingPlan> updatePlan(
    String id, {
    required String name,
    required int amountCents,
  }) =>
      _call(() async {
        final response = await _dio.put<Map<String, dynamic>>(
          '/v1/billing/plans/$id',
          data: {'name': name, 'amount_cents': amountCents},
        );
        return BillingPlan.fromJson(response.data!);
      });

  Future<BillingPlan> archivePlan(String id) => _call(() async {
        final response = await _dio
            .post<Map<String, dynamic>>('/v1/billing/plans/$id/archive');
        return BillingPlan.fromJson(response.data!);
      });

  // ---- Assinaturas ----

  Future<List<Subscription>> subscriptions({String? studentId}) =>
      _call(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/v1/billing/subscriptions',
          queryParameters: {if (studentId != null) 'student_id': studentId},
        );
        return [
          for (final raw in response.data!['items'] as List<dynamic>? ?? [])
            Subscription.fromJson(raw as Map<String, dynamic>),
        ];
      });

  /// Cria a assinatura; `amountCents` nulo usa o valor do plano. A fatura do
  /// mês de início, se cair no mês corrente, vem junto.
  Future<Subscription> createSubscription({
    required String studentId,
    required String planId,
    int? amountCents,
    required int dueDay,
    required DateTime startsOn,
  }) =>
      _call(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/v1/billing/subscriptions',
          data: {
            'student_id': studentId,
            'billing_plan_id': planId,
            if (amountCents != null) 'amount_cents': amountCents,
            'due_day': dueDay,
            'starts_on': formatCivilDay(startsOn),
          },
        );
        return Subscription.fromJson(
          response.data!['subscription'] as Map<String, dynamic>,
        );
      });

  /// Valor e vencimento valem a partir da próxima fatura.
  Future<Subscription> patchSubscription(
    String id, {
    int? amountCents,
    int? dueDay,
  }) =>
      _call(() async {
        final response = await _dio.patch<Map<String, dynamic>>(
          '/v1/billing/subscriptions/$id',
          data: {
            if (amountCents != null) 'amount_cents': amountCents,
            if (dueDay != null) 'due_day': dueDay,
          },
        );
        return Subscription.fromJson(response.data!);
      });

  /// `action`: `pause`, `resume` ou `cancel`.
  Future<Subscription> transitionSubscription(String id, String action) =>
      _call(() async {
        final response = await _dio.post<Map<String, dynamic>>(
            '/v1/billing/subscriptions/$id/$action',);
        return Subscription.fromJson(response.data!);
      });

  // ---- Faturas ----

  Future<InvoicePage> invoices({
    String? status,
    String? period,
    String? studentId,
    String? cursor,
    int limit = 50,
  }) =>
      _call(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/v1/billing/invoices',
          queryParameters: {
            if (status != null) 'status': status,
            if (period != null) 'period': period,
            if (studentId != null) 'student_id': studentId,
            if (cursor != null) 'cursor': cursor,
            'limit': limit,
          },
        );
        return _page(response.data!);
      });

  /// Fatura com o histórico de pagamentos e estornos.
  Future<Invoice> invoice(String id) => _call(() async {
        final response =
            await _dio.get<Map<String, dynamic>>('/v1/billing/invoices/$id');
        return Invoice.fromJson(response.data!);
      });

  /// Baixa integral. `idempotencyKey` repetida na mesma fatura devolve o mesmo
  /// pagamento (repetir depois de uma queda de rede não duplica). `paidOn`
  /// nulo = agora.
  Future<Invoice> recordPayment(
    String invoiceId, {
    required String idempotencyKey,
    DateTime? paidOn,
    String? note,
  }) =>
      _call(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/v1/billing/invoices/$invoiceId/payments',
          data: {
            if (paidOn != null) 'paid_at': formatCivilDay(paidOn),
            if (note != null && note.isNotEmpty) 'note': note,
          },
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        );
        return Invoice.fromJson(
            response.data!['invoice'] as Map<String, dynamic>,);
      });

  /// Só owner. O motivo é obrigatório; a fatura volta a `open`/`overdue`.
  Future<Invoice> reversePayment(String paymentId, {required String note}) =>
      _call(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/v1/billing/payments/$paymentId/reverse',
          data: {'note': note},
        );
        return Invoice.fromJson(
            response.data!['invoice'] as Map<String, dynamic>,);
      });

  /// Status derivado `ok|delinquent|none` por aluno, sem valores. Quem está
  /// fora do vínculo do professor não vem no mapa.
  Future<Map<String, String>> studentStatuses(List<String> ids) =>
      _call(() async {
        if (ids.isEmpty) return const <String, String>{};
        final response = await _dio.get<Map<String, dynamic>>(
          '/v1/billing/students/status',
          queryParameters: {'ids': ids.join(',')},
        );
        return {
          for (final e in response.data!.entries) e.key: e.value as String,
        };
      });

  /// Faturas do próprio aluno (somente leitura).
  Future<InvoicePage> myInvoices({String? cursor, int limit = 50}) =>
      _call(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/v1/me/invoices',
          queryParameters: {
            if (cursor != null) 'cursor': cursor,
            'limit': limit,
          },
        );
        return _page(response.data!);
      });

  InvoicePage _page(Map<String, dynamic> data) => InvoicePage(
        items: [
          for (final raw in data['items'] as List<dynamic>? ?? [])
            Invoice.fromJson(raw as Map<String, dynamic>),
        ],
        nextCursor: data['next_cursor'] as String?,
      );

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      final error = e.error;
      if (error is ApiException) {
        // `plan_archived` também existe no `workout` (plano de treino): aqui é
        // o plano de mensalidade, com mensagem própria.
        if (error.code == 'plan_archived') {
          throw ApiException(
            code: 'billing_plan_archived',
            params: error.params,
            statusCode: error.statusCode,
          );
        }
        throw error;
      }
      throw const ApiException.network();
    }
  }
}

/// `yyyy-MM-dd` de um dia civil.
String formatCivilDay(DateTime day) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${day.year.toString().padLeft(4, '0')}-${two(day.month)}-${two(day.day)}';
}

final billingRepositoryProvider = Provider<BillingRepository>((ref) {
  return BillingRepository(ref.watch(billingApiClientProvider).dio);
});
