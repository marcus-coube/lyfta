import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../chat/data/participant_directory.dart';
import '../../students/domain/student.dart';
import '../../students/presentation/students_controller.dart';
import '../data/dashboard_repository.dart';
import '../domain/dashboard_models.dart';

/// Filtro por professor do owner (nulo = todos). O coach não tem filtro: o
/// servidor já devolve só o vínculo dele.
final dashboardCoachFilterProvider = StateProvider<String?>((ref) => null);

/// Professores para o filtro do owner; falhar só esconde o filtro.
final dashboardCoachOptionsProvider =
    FutureProvider.autoDispose<List<CoachOption>>((ref) {
  return ref.watch(studentRepositoryProvider).listCoaches();
});

// Um provider por card: cada um carrega, falha e tenta de novo sozinho.

final dashboardStudentStatsProvider =
    FutureProvider.autoDispose<StudentStats>((ref) {
  final coach = ref.watch(dashboardCoachFilterProvider);
  return ref.watch(dashboardRepositoryProvider).studentStats(coachId: coach);
});

final dashboardCheckinsProvider = FutureProvider.autoDispose<int>((ref) {
  final coach = ref.watch(dashboardCoachFilterProvider);
  return ref
      .watch(dashboardRepositoryProvider)
      .unreviewedCheckins(coachId: coach);
});

final dashboardTodayProvider = FutureProvider.autoDispose<CoachToday>((ref) {
  final coach = ref.watch(dashboardCoachFilterProvider);
  return ref.watch(dashboardRepositoryProvider).coachToday(coachId: coach);
});

final dashboardBillingProvider =
    FutureProvider.autoDispose<BillingSummary>((ref) {
  return ref.watch(dashboardRepositoryProvider).billingSummary();
});

/// Nomes dos alunos que aparecem nas listas (o `workout` só devolve ids). Se o
/// diretório falhar, as listas mostram um rótulo genérico em vez de quebrar.
final dashboardNamesProvider = FutureProvider.autoDispose
    .family<Map<String, String>, String>((ref, idsKey) async {
  if (idsKey.isEmpty) return const {};
  try {
    return await ref
        .watch(participantDirectoryRepositoryProvider)
        .names(idsKey.split(','));
  } catch (_) {
    return const {};
  }
});
