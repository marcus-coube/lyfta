import 'package:dio/dio.dart';
import 'package:lyfta/core/http/api_exception.dart';
import 'package:lyfta/features/dashboard/data/dashboard_repository.dart';
import 'package:lyfta/features/dashboard/domain/dashboard_models.dart';

/// Repositório do dashboard em memória: devolve o seed ou falha por serviço.
class FakeDashboardRepository extends DashboardRepository {
  FakeDashboardRepository({
    this.stats = const StudentStats(
      active: 12,
      inactive: 3,
      pendingInvites: 2,
      newThisMonth: 4,
    ),
    this.unreviewed = 5,
    CoachToday? today,
    BillingSummary? summary,
  })  : today = today ?? defaultToday(),
        summary = summary ?? defaultSummary(),
        super(identity: Dio(), workout: Dio(), billing: Dio(), comms: Dio());

  final StudentStats stats;
  final int unreviewed;
  CoachToday today;
  BillingSummary summary;

  /// Serviços "fora do ar" (a chamada lança erro de rede).
  bool todayDown = false;
  bool billingDown = false;

  int billingCalls = 0;
  int todayCalls = 0;
  final coachIds = <String?>[];

  static CoachToday defaultToday() {
    final now = DateTime.now();
    return CoachToday(
      items: [
        const TodayItem(studentId: 's-trained', state: TodayState.trained),
        const TodayItem(studentId: 's-going', state: TodayState.inProgress),
        TodayItem(
          studentId: 's-stalled',
          state: TodayState.pending,
          lastSessionAt: now.subtract(const Duration(days: 9)),
          stale: true,
        ),
        // Nunca treinou: stale no servidor, mas fora do card "sem treinar".
        const TodayItem(
          studentId: 's-new',
          state: TodayState.pending,
          stale: true,
        ),
        const TodayItem(
          studentId: 's-noplan',
          state: TodayState.noPlan,
          stale: true,
        ),
      ],
    );
  }

  static BillingSummary defaultSummary() => const BillingSummary(
        period: '2026-11',
        currency: 'BRL',
        receivedCents: 150000,
        toReceiveCents: 90000,
        toReceiveCount: 3,
        overdueCents: 30000,
        overdueCount: 1,
        delinquentStudents: 1,
        series: [
          MonthReceived(period: '2026-06', receivedCents: 100000),
          MonthReceived(period: '2026-07', receivedCents: 120000),
          MonthReceived(period: '2026-08', receivedCents: 0),
          MonthReceived(period: '2026-09', receivedCents: 90000),
          MonthReceived(period: '2026-10', receivedCents: 110000),
          MonthReceived(period: '2026-11', receivedCents: 150000),
        ],
      );

  @override
  Future<StudentStats> studentStats({String? coachId}) async {
    coachIds.add(coachId);
    return stats;
  }

  @override
  Future<int> unreviewedCheckins({String? coachId}) async => unreviewed;

  @override
  Future<CoachToday> coachToday({String? coachId}) async {
    todayCalls++;
    if (todayDown) throw const ApiException.network();
    return today;
  }

  @override
  Future<BillingSummary> billingSummary() async {
    billingCalls++;
    if (billingDown) throw const ApiException.network();
    return summary;
  }
}
