import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/auth/auth_controller.dart';
import 'package:lyfta/core/auth/auth_state.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/http/api_exception.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/billing/data/billing_repository.dart';
import 'package:lyfta/features/billing/domain/billing_models.dart';
import 'package:lyfta/features/billing/presentation/billing_providers.dart';
import 'package:lyfta/features/builder/data/plan_repository.dart';
import 'package:lyfta/features/evolution/domain/evolution_scope.dart';
import 'package:lyfta/features/profile/data/profile_repository.dart';
import 'package:lyfta/features/profile/domain/student_profile.dart';
import 'package:lyfta/features/students/data/student_repository.dart';
import 'package:lyfta/features/students/domain/student.dart';
import 'package:lyfta/features/students/presentation/student_data_tab.dart';
import 'package:lyfta/features/students/presentation/students_controller.dart';
import 'package:lyfta/shared/domain/plan.dart';

import '../billing/billing_fakes.dart';

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
  _FakeStudents(this.current) : super(Dio());

  Student current;
  final updates = <Map<String, String?>>[];
  final deactivations = <String?>[];
  final reactivations = <String?>[];
  final resent = <String>[];
  final reassigned = <(String, String)>[];
  Object? deactivateError;

  @override
  Future<StudentPage> list({
    String query = '',
    StudentStatusFilter status = StudentStatusFilter.active,
    String? coachId,
    String? cursor,
    int? limit,
  }) async =>
      const StudentPage(items: []);

  @override
  Future<Student> get(String id) async => current;

  @override
  Future<Student> update(
    String id, {
    String? name,
    String? phone,
    String? birthDate,
  }) async {
    updates.add({'name': name, 'phone': phone, 'birth': birthDate});
    return current;
  }

  @override
  Future<void> deactivate(String id, {String? reason}) async {
    if (deactivateError != null) throw deactivateError!;
    deactivations.add(reason);
  }

  @override
  Future<void> reactivate(String id, {String? reason}) async {
    reactivations.add(reason);
  }

  @override
  Future<List<StatusEvent>> statusHistory(String id) async => [
        StatusEvent(
          from: 'invited',
          to: 'active',
          changedByName: 'Ana Alves',
          createdAt: DateTime(2026, 11, 1, 9, 30),
        ),
      ];

  @override
  Future<void> resendInvitation(String invitationId) async {
    resent.add(invitationId);
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

/// A aba Dados carrega a anamnese (P5.5); aqui ela vem vazia e sem lesões.
class _FakeProfiles extends ProfileRepository {
  _FakeProfiles() : super(Dio());

  @override
  Future<StudentProfile> profile(EvolutionScope scope) async =>
      const StudentProfile();

  @override
  Future<List<Injury>> injuries(EvolutionScope scope) async => const [];
}

const _active = Student(
  id: 'aluno-1',
  name: 'Ana Alves',
  email: 'ana@example.com',
  status: 'active',
  coachId: 'coach-a',
  coachName: 'Coach Alfa',
  phone: '11999990000',
);

Future<_FakeStudents> _pump(
  WidgetTester tester,
  Student student, {
  bool isOwner = false,
  FakeBillingRepository? billing,
  BillingAccess access = BillingAccess.none,
}) async {
  final fake = _FakeStudents(student);
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _TestAuth(isOwner: isOwner)),
        studentRepositoryProvider.overrideWithValue(fake),
        planRepositoryProvider.overrideWithValue(_FakePlans()),
        profileRepositoryProvider.overrideWithValue(_FakeProfiles()),
        billingAccessProvider.overrideWithValue(access),
        billingRepositoryProvider
            .overrideWithValue(billing ?? FakeBillingRepository()),
      ],
      child: MaterialApp(
        theme: LyTheme.dark(),
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: StudentDataTab(student: student)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets(
      'edita o cadastro: salvar só habilita com mudança e manda o PATCH',
      (tester) async {
    final fake = await _pump(tester, _active);

    final save = find.byKey(const Key('student_save'));
    // Sem mudança, o botão está desabilitado: tocar não manda nada.
    await tester.tap(save, warnIfMissed: false);
    await tester.pump();
    expect(fake.updates, isEmpty);

    await tester.enterText(
      find.byKey(const Key('student_phone')),
      '21988887777',
    );
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(fake.updates, hasLength(1));
    expect(fake.updates.single['phone'], '21988887777');
    expect(fake.updates.single['name'], 'Ana Alves');
    // Sem nascimento no cadastro: "" apaga, não mantém.
    expect(fake.updates.single['birth'], '');
    expect(find.text('Dados salvos.'), findsOneWidget);
  });

  testWidgets('inativar pede confirmação e manda o motivo', (tester) async {
    final fake = await _pump(tester, _active);

    await tester.tap(find.byKey(const Key('student_deactivate')));
    await tester.pumpAndSettle();
    expect(find.text('Inativar Ana Alves?'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('student_status_reason')),
      'Trancou a matrícula',
    );
    await tester.tap(find.byKey(const Key('student_status_confirm')));
    await tester.pumpAndSettle();

    expect(fake.deactivations, ['Trancou a matrícula']);
    expect(find.text('Aluno inativado.'), findsOneWidget);
  });

  testWidgets('cancelar a confirmação não inativa', (tester) async {
    final fake = await _pump(tester, _active);

    await tester.tap(find.byKey(const Key('student_deactivate')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(fake.deactivations, isEmpty);
  });

  testWidgets('aluno já inativo no servidor: mostra a mensagem do 409',
      (tester) async {
    final fake = await _pump(tester, _active);
    fake.deactivateError =
        const ApiException(code: 'already_inactive', statusCode: 409);

    await tester.tap(find.byKey(const Key('student_deactivate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('student_status_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Este aluno já está inativo.'), findsOneWidget);
  });

  testWidgets('inativo oferece reativar e não inativar', (tester) async {
    final fake = await _pump(
      tester,
      const Student(
        id: 'aluno-1',
        name: 'Ana Alves',
        email: 'ana@example.com',
        status: 'inactive',
      ),
    );

    expect(find.byKey(const Key('student_deactivate')), findsNothing);
    await tester.tap(find.byKey(const Key('student_reactivate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('student_status_confirm')));
    await tester.pumpAndSettle();

    expect(fake.reactivations, ['']);
  });

  testWidgets('convite pendente oferece reenviar', (tester) async {
    final fake = await _pump(
      tester,
      const Student(
        id: 'aluno-1',
        name: 'Ana Alves',
        email: 'ana@example.com',
        status: 'invited',
        pendingInvitation: PendingInvitation(id: 'inv-1', expired: true),
      ),
    );

    expect(find.byKey(const Key('student_deactivate')), findsNothing);
    expect(find.textContaining('O convite expirou'), findsOneWidget);
    await tester.tap(find.byKey(const Key('student_invite_resend')));
    await tester.pumpAndSettle();

    expect(fake.resent, ['inv-1']);
  });

  testWidgets('histórico lista a mudança com autor', (tester) async {
    await _pump(tester, _active);

    expect(find.text('Convite pendente → Ativo'), findsOneWidget);
    expect(find.textContaining('por Ana Alves'), findsOneWidget);
  });

  testWidgets('coach sem owner não vê "trocar professor"', (tester) async {
    await _pump(tester, _active);
    expect(find.byKey(const Key('student_change_coach')), findsNothing);
  });

  testWidgets('owner troca o professor pelo seletor', (tester) async {
    final fake = await _pump(tester, _active, isOwner: true);
    await tester.tap(find.byKey(const Key('student_change_coach')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coach Beta'));
    await tester.pumpAndSettle();

    expect(fake.reassigned, [('aluno-1', 'coach-b')]);
  });

  testWidgets(
      'inativar aluno com assinatura ativa oferece o atalho para cancelar',
      (tester) async {
    final billing = FakeBillingRepository(
      plans: [
        const BillingPlan(
          id: 'plan-1',
          name: 'Mensal',
          amountCents: 15000,
          currency: 'BRL',
          active: true,
        ),
      ],
      subscriptions: [
        Subscription(
          id: 'sub-1',
          studentId: 'aluno-1',
          billingPlanId: 'plan-1',
          amountCents: 15000,
          currency: 'BRL',
          dueDay: 10,
          startsOn: DateTime(2026, 10, 1),
          status: 'active',
          customer: const BillingCustomer(name: 'Ana Alves', email: 'a@x.com'),
        ),
      ],
    );
    final fake = await _pump(
      tester,
      _active,
      billing: billing,
      access: BillingAccess.owner,
    );

    await tester.tap(find.byKey(const Key('student_deactivate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('student_status_confirm')));
    await tester.pumpAndSettle();

    expect(fake.deactivations, hasLength(1));
    expect(find.text('Assinatura ainda ativa'), findsOneWidget);

    await tester.tap(find.byKey(const Key('student_cancel_subscription')));
    await tester.pumpAndSettle();
    expect(billing.transitions, [('sub-1', 'cancel')]);
  });

  testWidgets('inativar sem assinatura ativa não mostra o aviso',
      (tester) async {
    await _pump(
      tester,
      _active,
      billing: FakeBillingRepository(),
      access: BillingAccess.owner,
    );

    await tester.tap(find.byKey(const Key('student_deactivate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('student_status_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Assinatura ainda ativa'), findsNothing);
  });

  testWidgets('coach só com status vê o selo, sem aviso nem valores',
      (tester) async {
    await _pump(
      tester,
      _active,
      billing: FakeBillingRepository(statuses: {'aluno-1': 'delinquent'}),
      access: BillingAccess.statusOnly,
    );

    expect(find.byKey(const Key('delinquent_badge')), findsOneWidget);
  });
}
