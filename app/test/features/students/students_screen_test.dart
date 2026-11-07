import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/auth/auth_controller.dart';
import 'package:lyfta/core/auth/auth_state.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/builder/data/plan_repository.dart';
import 'package:lyfta/features/students/data/student_repository.dart';
import 'package:lyfta/features/students/domain/student.dart';
import 'package:lyfta/features/students/presentation/students_controller.dart';
import 'package:lyfta/features/students/presentation/students_screen.dart';
import 'package:lyfta/shared/domain/plan.dart';

class _TestAuth extends AuthController {
  _TestAuth({required this.isOwner});

  final bool isOwner;

  @override
  AuthState build() => AuthState.authenticated(
        roles: {UserRole.coach},
        tenantId: 'tenant-1',
        userId: 'user-1',
        isOwner: isOwner,
      );
}

class _FakePlans extends PlanRepository {
  _FakePlans() : super(Dio());

  @override
  Future<List<PlanSummary>> byStudent(String studentId) async => const [];
}

class _FakeStudents extends StudentRepository {
  _FakeStudents() : super(Dio());

  final reassigned = <(String, String)>[];

  @override
  Future<StudentPage> list({
    String query = '',
    String? cursor,
    int? limit,
  }) async {
    return const StudentPage(
      items: [
        Student(
          id: 'aluno-1',
          name: 'Ana Alves',
          email: 'ana@example.com',
          status: 'active',
          coachId: 'coach-a',
          coachName: 'Coach Alfa',
        ),
      ],
    );
  }

  @override
  Future<List<CoachOption>> listCoaches() async => const [
        CoachOption(id: 'coach-a', name: 'Coach Alfa'),
        CoachOption(id: 'coach-b', name: 'Coach Beta'),
      ];

  @override
  Future<void> reassignCoach({
    required String studentId,
    required String coachId,
  }) async {
    reassigned.add((studentId, coachId));
  }
}

Future<_FakeStudents> _pump(
  WidgetTester tester, {
  required bool isOwner,
}) async {
  final students = _FakeStudents();
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _TestAuth(isOwner: isOwner)),
        studentRepositoryProvider.overrideWithValue(students),
        planRepositoryProvider.overrideWithValue(_FakePlans()),
      ],
      child: MaterialApp(
        theme: LyTheme.dark(),
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const StudentsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return students;
}

void main() {
  testWidgets('owner vê o professor do aluno e troca pelo seletor',
      (tester) async {
    final students = await _pump(tester, isOwner: true);

    expect(find.text('Ana Alves'), findsOneWidget);
    expect(find.text('Professor: Coach Alfa'), findsOneWidget);

    await tester.tap(find.byTooltip('Trocar professor'));
    await tester.pumpAndSettle();
    expect(find.text('Professor de Ana Alves'), findsOneWidget);

    await tester.tap(find.text('Coach Beta'));
    await tester.pumpAndSettle();

    expect(students.reassigned, [('aluno-1', 'coach-b')]);
  });

  testWidgets('coach sem owner não vê professor nem a ação de trocar',
      (tester) async {
    await _pump(tester, isOwner: false);

    expect(find.text('Ana Alves'), findsOneWidget);
    expect(find.textContaining('Professor:'), findsNothing);
    expect(find.byTooltip('Trocar professor'), findsNothing);
  });
}
