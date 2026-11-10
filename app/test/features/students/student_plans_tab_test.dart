import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/auth/auth_controller.dart';
import 'package:lyfta/core/auth/auth_state.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/builder/data/plan_repository.dart';
import 'package:lyfta/features/students/data/student_overview_repository.dart';
import 'package:lyfta/features/students/data/student_repository.dart';
import 'package:lyfta/features/students/domain/student.dart';
import 'package:lyfta/features/students/presentation/student_plans_tab.dart';
import 'package:lyfta/features/students/presentation/students_controller.dart';
import 'package:lyfta/shared/domain/plan.dart';

class _TestAuth extends AuthController {
  @override
  AuthState build() => AuthState.authenticated(
        roles: {UserRole.coach},
        tenantId: 't',
        userId: 'u',
      );
}

class _FakeStudents extends StudentRepository {
  _FakeStudents() : super(Dio());

  @override
  Future<StudentPage> list({
    String query = '',
    StudentStatusFilter status = StudentStatusFilter.active,
    String? coachId,
    String? cursor,
    int? limit,
  }) async =>
      const StudentPage(items: []);
}

class _FakeOverview extends StudentOverviewRepository {
  _FakeOverview() : super(Dio());
}

class _FakePlans extends PlanRepository {
  _FakePlans() : super(Dio());

  final activated = <String>[];
  final duplicated = <String>[];
  final archived = <String>[];
  final nextDays = <String>[];

  @override
  Future<Plan> byId(String id, {String? version}) async => Plan(
        id: id,
        studentId: 's1',
        title: 'Plano em uso',
        status: 'published',
        nextDayId: 'dB',
        days: [
          WorkoutDay(id: 'dA', label: 'A', title: 'Peito'),
          WorkoutDay(id: 'dB', label: 'B'),
          WorkoutDay(id: 'dC', label: 'C'),
        ],
        versions: const [],
      );

  @override
  Future<void> setNextDay({
    required String studentId,
    required String dayId,
  }) async =>
      nextDays.add(dayId);

  @override
  Future<List<PlanSummary>> byStudent(String studentId) async => const [
        PlanSummary(
          id: 'old',
          title: 'Plano antigo',
          status: 'archived',
          publishedVersionNo: 2,
          hasDraft: false,
          isActive: false,
        ),
        PlanSummary(
          id: 'draft',
          title: 'Rascunho novo',
          status: 'draft',
          publishedVersionNo: 0,
          hasDraft: true,
          isActive: false,
        ),
        PlanSummary(
          id: 'ruim',
          title: 'Arquivado sem versão',
          status: 'archived',
          publishedVersionNo: 0,
          hasDraft: true,
          isActive: false,
        ),
        PlanSummary(
          id: 'live',
          title: 'Plano em uso',
          status: 'published',
          publishedVersionNo: 3,
          hasDraft: false,
          isActive: true,
        ),
      ];

  @override
  Future<void> activate({
    required String studentId,
    required String planId,
  }) async =>
      activated.add(planId);

  @override
  Future<Plan> duplicate(String planId, {String? studentId}) async {
    duplicated.add(planId);
    return const Plan(
      id: 'copy',
      studentId: 's1',
      title: 'cópia',
      status: 'draft',
      days: [],
      versions: [],
    );
  }

  @override
  Future<void> archive(String planId) async => archived.add(planId);
}

Future<_FakePlans> _pump(WidgetTester tester) async {
  final plans = _FakePlans();
  tester.view.physicalSize = const Size(700, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_TestAuth.new),
        planRepositoryProvider.overrideWithValue(plans),
        studentRepositoryProvider.overrideWithValue(_FakeStudents()),
        studentOverviewRepositoryProvider.overrideWithValue(_FakeOverview()),
      ],
      child: MaterialApp(
        theme: LyTheme.dark(),
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: StudentPlansTab(studentId: 's1')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return plans;
}

void main() {
  testWidgets('plano em uso vem primeiro e destacado; arquivados por último',
      (tester) async {
    await _pump(tester);

    final live = tester.getTopLeft(find.byKey(const Key('plan_card_live')));
    final draft = tester.getTopLeft(find.byKey(const Key('plan_card_draft')));
    final old = tester.getTopLeft(find.byKey(const Key('plan_card_old')));
    expect(live.dy, lessThan(draft.dy));
    expect(draft.dy, lessThan(old.dy));
    expect(find.textContaining('Em uso'), findsOneWidget);
    expect(find.textContaining('Arquivado'), findsNWidgets(3));
  });

  testWidgets('ativar o arquivado pede confirmação e chama o activate',
      (tester) async {
    final plans = await _pump(tester);

    await tester.tap(find.byKey(const Key('plan_menu_old')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ativar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('rotação recomeça'), findsOneWidget);
    await tester.tap(find.byKey(const Key('plan_confirm')));
    await tester.pumpAndSettle();

    expect(plans.activated, ['old']);
  });

  testWidgets(
      'arquivado nunca publicado só oferece duplicar; ativo não arquiva',
      (tester) async {
    final plans = await _pump(tester);

    await tester.tap(find.byKey(const Key('plan_menu_ruim')));
    await tester.pumpAndSettle();
    expect(find.text('Ativar'), findsNothing);
    expect(find.text('Arquivar'), findsNothing);
    await tester.tap(find.text('Duplicar'));
    await tester.pumpAndSettle();
    expect(plans.duplicated, ['ruim']);

    await tester.tap(find.byKey(const Key('plan_menu_live')));
    await tester.pumpAndSettle();
    expect(find.text('Arquivar'), findsNothing);
    expect(find.text('Ativar'), findsNothing);
  });

  testWidgets('próximo dia: só no plano em uso, marca o atual e envia o escolhido',
      (tester) async {
    final plans = await _pump(tester);

    await tester.tap(find.byKey(const Key('plan_menu_old')));
    await tester.pumpAndSettle();
    expect(find.text('Próximo dia'), findsNothing);
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('plan_menu_live')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Próximo dia'));
    await tester.pumpAndSettle();

    expect(find.text('Próximo agora'), findsOneWidget);
    await tester.tap(find.byKey(const Key('next_day_dC')));
    await tester.pumpAndSettle();

    expect(plans.nextDays, ['dC']);
    expect(find.text('Próximo dia: C.'), findsOneWidget);
  });
}
