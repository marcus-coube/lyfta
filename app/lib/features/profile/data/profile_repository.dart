import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/http/api_exception.dart';
import '../../../core/http/providers.dart';
import '../../evolution/domain/evolution_scope.dart';
import '../domain/student_profile.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(assessmentApiClientProvider).dio);
});

String _isoDay(DateTime day) => DateFormat('yyyy-MM-dd').format(day);

/// Anamnese e lesões sobre o `assessment` (P5.3). As duas portas têm o mesmo
/// formato, então o [EvolutionScope] resolve o prefixo (`/v1/me` ou
/// `/v1/students/{id}`) como nas demais telas de saúde.
class ProfileRepository {
  ProfileRepository(this._dio);

  final Dio _dio;

  Future<StudentProfile> profile(EvolutionScope scope) => _call(() async {
        final response =
            await _dio.get<Map<String, dynamic>>('${scope.basePath}/profile');
        return StudentProfile.fromJson(response.data!);
      });

  /// Grava a anamnese inteira. A chave `coach_notes` só vai na porta do
  /// coach — o aluno nunca a escreve (o servidor a ignoraria de qualquer jeito).
  Future<StudentProfile> saveProfile(
    EvolutionScope scope,
    StudentProfile profile,
  ) =>
      _call(() async {
        final response = await _dio.put<Map<String, dynamic>>(
          '${scope.basePath}/profile',
          data: {
            'goal': profile.goal,
            'goal_notes': profile.goalNotes,
            'training_experience': profile.trainingExperience,
            'weekly_target': profile.weeklyTarget,
            'medical_notes': profile.medicalNotes,
            if (scope.isCoach) 'coach_notes': profile.coachNotes,
          },
        );
        return StudentProfile.fromJson(response.data!);
      });

  Future<List<Injury>> injuries(EvolutionScope scope) => _call(() async {
        final response =
            await _dio.get<Map<String, dynamic>>('${scope.basePath}/injuries');
        return (response.data!['items'] as List<dynamic>? ?? const [])
            .map((raw) => Injury.fromJson(raw as Map<String, dynamic>))
            .toList();
      });

  Future<Injury> addInjury(EvolutionScope scope, InjuryInput input) =>
      _call(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '${scope.basePath}/injuries',
          data: {
            'body_region': input.bodyRegion,
            'description': input.description,
            if (input.since != null) 'since': _isoDay(input.since!),
          },
        );
        return Injury.fromJson(response.data!);
      });

  /// Resolve (data) ou reabre (`null`) a lesão — o PATCH aceita `null`.
  Future<Injury> setResolved(
    EvolutionScope scope,
    String injuryId,
    DateTime? resolvedAt,
  ) =>
      _call(() async {
        final response = await _dio.patch<Map<String, dynamic>>(
          '${scope.basePath}/injuries/$injuryId',
          data: {
            'resolved_at': resolvedAt == null ? null : _isoDay(resolvedAt),
          },
        );
        return Injury.fromJson(response.data!);
      });

  Future<void> deleteInjury(EvolutionScope scope, String injuryId) =>
      _call(() async {
        await _dio.delete<void>('${scope.basePath}/injuries/$injuryId');
      });

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      final error = e.error;
      if (error is ApiException) throw error;
      throw const ApiException.network();
    }
  }
}
