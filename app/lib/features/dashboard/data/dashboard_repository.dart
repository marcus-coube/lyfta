import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/http/api_exception.dart';
import '../../../core/http/providers.dart';
import '../domain/dashboard_models.dart';

/// Agregações do dashboard (P8.1): cada serviço responde o seu pedaço e o app
/// compõe, sem BFF (ADR-013). Quatro clientes, quatro chamadas independentes —
/// uma falhar não afeta as outras.
class DashboardRepository {
  DashboardRepository({
    required Dio identity,
    required Dio workout,
    required Dio billing,
    required Dio comms,
  })  : _identity = identity,
        _workout = workout,
        _billing = billing,
        _comms = comms;

  final Dio _identity;
  final Dio _workout;
  final Dio _billing;
  final Dio _comms;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      final error = e.error;
      if (error is ApiException) throw error;
      throw const ApiException.network();
    }
  }

  /// `coachId` só vale para o owner; o servidor ignora para o coach.
  Future<StudentStats> studentStats({String? coachId}) => _call(() async {
        final response = await _identity.get<Map<String, dynamic>>(
          '/v1/students/stats',
          queryParameters: {if (coachId != null) 'coach_id': coachId},
        );
        return StudentStats.fromJson(response.data!);
      });

  Future<CoachToday> coachToday({String? coachId}) => _call(() async {
        final response = await _workout.get<Map<String, dynamic>>(
          '/v1/coach/today',
          queryParameters: {if (coachId != null) 'coach_id': coachId},
        );
        return CoachToday.fromJson(response.data!);
      });

  /// Só o owner (o coach recebe 403). Sem filtro por professor: é do tenant.
  Future<BillingSummary> billingSummary() => _call(() async {
        final response =
            await _billing.get<Map<String, dynamic>>('/v1/billing/summary');
        return BillingSummary.fromJson(response.data!);
      });

  Future<int> unreviewedCheckins({String? coachId}) => _call(() async {
        final response = await _comms.get<Map<String, dynamic>>(
          '/v1/checkins/stats',
          queryParameters: {if (coachId != null) 'coach_id': coachId},
        );
        return response.data!['unreviewed'] as int? ?? 0;
      });
}

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(
    identity: ref.watch(identityApiClientProvider).dio,
    workout: ref.watch(workoutApiClientProvider).dio,
    billing: ref.watch(billingApiClientProvider).dio,
    comms: ref.watch(commsApiClientProvider).dio,
  );
});
