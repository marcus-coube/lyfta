import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../evolution/domain/evolution_scope.dart';
import '../data/profile_repository.dart';
import '../domain/student_profile.dart';

/// Anamnese do escopo (`me` ou aluno do coach). `autoDispose`: abrir a tela
/// sempre traz o dado do servidor.
final studentProfileProvider = FutureProvider.autoDispose
    .family<StudentProfile, EvolutionScope>((ref, scope) {
  return ref.watch(profileRepositoryProvider).profile(scope);
});

/// Lesões do escopo, ativas primeiro (mais recentes antes).
final injuriesProvider = FutureProvider.autoDispose
    .family<List<Injury>, EvolutionScope>((ref, scope) async {
  final list = await ref.watch(profileRepositoryProvider).injuries(scope);
  return [...list]..sort((a, b) {
      if (a.active != b.active) return a.active ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
});
