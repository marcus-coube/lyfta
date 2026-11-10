import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/auth/auth_controller.dart';
import 'package:lyfta/core/auth/auth_state.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/students/data/student_overview_repository.dart';
import 'package:lyfta/features/students/data/student_repository.dart';
import 'package:lyfta/features/students/domain/student.dart';
import 'package:lyfta/features/students/domain/student_overview.dart';
import 'package:lyfta/features/students/presentation/students_controller.dart';
import 'package:lyfta/features/students/presentation/students_screen.dart';

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

/// Resumo em lote em memória: conta as chamadas (uma por página, nunca por
/// linha) e dá plano + treino de ontem só a "Ana Alves".
class _FakeOverview extends StudentOverviewRepository {
  _FakeOverview() : super(Dio());

  final calls = <List<String>>[];
  bool fail = false;

  @override
  Future<Map<String, StudentOverview>> overview(List<String> ids) async {
    calls.add(ids);
    if (fail) throw Exception('workout fora do ar');
    return {
      if (ids.contains('id-Ana Alves'))
        'id-Ana Alves': StudentOverview(
          lastSessionAt: DateTime.now().subtract(const Duration(days: 1)),
          activePlan:
              const ActivePlan(id: 'p1', title: 'Hipertrofia', versionNo: 2),
        ),
    };
  }
}

/// Alunos em memória com paginação por cursor (o cursor é o índice).
class _FakeStudents extends StudentRepository {
  _FakeStudents(this.all) : super(Dio());

  final List<Student> all;
  final calls =
      <({String query, StudentStatusFilter status, String? coachId})>[];

  @override
  Future<StudentPage> list({
    String query = '',
    StudentStatusFilter status = StudentStatusFilter.active,
    String? coachId,
    String? cursor,
    int? limit,
  }) async {
    calls.add((query: query, status: status, coachId: coachId));
    final matching = all
        .where((s) => s.status == status.apiValue)
        .where((s) => coachId == null || s.coachId == coachId)
        .where((s) => s.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    final start = int.tryParse(cursor ?? '') ?? 0;
    final end = (start + (limit ?? 20)).clamp(0, matching.length);
    return StudentPage(
      items: matching.sublist(start, end),
      nextCursor: end < matching.length ? '$end' : null,
    );
  }

  @override
  Future<List<CoachOption>> listCoaches() async => const [
        CoachOption(id: 'coach-a', name: 'Coach Alfa'),
        CoachOption(id: 'coach-b', name: 'Coach Beta'),
      ];
}

Student _student(
  String name, {
  String status = 'active',
  String coachId = 'coach-a',
}) {
  return Student(
    id: 'id-$name',
    name: name,
    email: '${name.toLowerCase().replaceAll(' ', '.')}@example.com',
    status: status,
    coachId: coachId,
    coachName: coachId == 'coach-a' ? 'Coach Alfa' : 'Coach Beta',
  );
}

Future<_FakeStudents> _pump(
  WidgetTester tester,
  List<Student> students, {
  bool isOwner = false,
  Size size = const Size(900, 1600),
  _FakeOverview? overview,
}) async {
  final fake = _FakeStudents(students);
  overview ??= _FakeOverview();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _TestAuth(isOwner: isOwner)),
        studentRepositoryProvider.overrideWithValue(fake),
        studentOverviewRepositoryProvider.overrideWithValue(overview),
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
  return fake;
}

void main() {
  testWidgets('tela larga vira tabela; owner vê a coluna Professor',
      (tester) async {
    await _pump(tester, [_student('Ana Alves')], isOwner: true);

    expect(find.text('Ana Alves'), findsOneWidget);
    expect(find.text('Aluno'), findsOneWidget); // cabeçalho da tabela
    expect(find.text('Professor'), findsOneWidget);
    expect(find.text('Coach Alfa'), findsWidgets);
  });

  testWidgets('tabela traz plano e último treino com uma chamada por página',
      (tester) async {
    final overview = _FakeOverview();
    await _pump(
      tester,
      [_student('Ana Alves'), _student('Bruno Costa')],
      overview: overview,
    );

    expect(find.text('Último treino'), findsOneWidget);
    expect(find.text('Ontem'), findsOneWidget);
    expect(find.text('Nunca treinou'), findsOneWidget); // Bruno
    expect(find.text('Hipertrofia · v2'), findsOneWidget);
    expect(overview.calls, hasLength(1));
    expect(overview.calls.single, ['id-Ana Alves', 'id-Bruno Costa']);
  });

  testWidgets('workout fora do ar: a lista aparece sem plano nem treino',
      (tester) async {
    await _pump(
      tester,
      [_student('Ana Alves')],
      overview: _FakeOverview()..fail = true,
    );

    expect(find.text('Ana Alves'), findsOneWidget);
    expect(find.text('Sem plano'), findsOneWidget);
    expect(find.text('Nunca treinou'), findsOneWidget);
  });

  testWidgets('coach sem owner não vê a coluna nem o filtro de professor',
      (tester) async {
    await _pump(tester, [_student('Ana Alves')]);

    expect(find.text('Ana Alves'), findsOneWidget);
    expect(find.text('Professor'), findsNothing);
    expect(find.byKey(const Key('students_filter_coach')), findsNothing);
  });

  testWidgets('celular mostra cartões com o professor só para o owner',
      (tester) async {
    await _pump(
      tester,
      [_student('Ana Alves')],
      isOwner: true,
      size: const Size(400, 800),
    );

    expect(find.text('Aluno'), findsNothing);
    expect(find.text('Professor: Coach Alfa'), findsOneWidget);
  });

  testWidgets('filtro de status troca a consulta e mostra o estado vazio',
      (tester) async {
    final fake = await _pump(tester, [
      _student('Ana Alves'),
      _student('Bia Braga', status: 'inactive'),
    ]);

    expect(find.text('Ana Alves'), findsOneWidget);
    expect(find.text('Bia Braga'), findsNothing);

    await tester.tap(find.byKey(const Key('students_filter_inactive')));
    await tester.pumpAndSettle();
    expect(find.text('Bia Braga'), findsOneWidget);
    expect(find.text('Ana Alves'), findsNothing);
    expect(fake.calls.last.status, StudentStatusFilter.inactive);

    await tester.tap(find.byKey(const Key('students_filter_invited')));
    await tester.pumpAndSettle();
    expect(
      find.text('Nenhum aluno encontrado com esses filtros.'),
      findsOneWidget,
    );
  });

  testWidgets('busca espera parar de digitar e filtra por nome',
      (tester) async {
    final fake = await _pump(tester, [
      _student('Ana Alves'),
      _student('Bruno Costa'),
    ]);

    await tester.enterText(find.byType(TextField).first, 'bru');
    await tester.pump(const Duration(milliseconds: 100));
    expect(fake.calls.where((c) => c.query == 'bru'), isEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Bruno Costa'), findsOneWidget);
    expect(find.text('Ana Alves'), findsNothing);
  });

  testWidgets('filtro de professor (owner) manda coach_id', (tester) async {
    final fake = await _pump(
      tester,
      [_student('Ana Alves'), _student('Caio Dias', coachId: 'coach-b')],
      isOwner: true,
    );

    await tester.tap(find.byKey(const Key('students_filter_coach')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coach Beta').last);
    await tester.pumpAndSettle();

    expect(fake.calls.last.coachId, 'coach-b');
    expect(find.text('Caio Dias'), findsOneWidget);
    expect(find.text('Ana Alves'), findsNothing);
  });

  testWidgets('250 alunos: a lista rola sem teto até o último', (tester) async {
    final students = [
      for (var i = 1; i <= 250; i++)
        _student('Aluno ${i.toString().padLeft(3, '0')}'),
    ];
    await _pump(tester, students);

    await tester.scrollUntilVisible(
      find.text('Aluno 250'),
      600,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 400,
    );
    await tester.pumpAndSettle();

    expect(find.text('Aluno 250'), findsOneWidget);
  });

  testWidgets('janela muito baixa: o cabeçalho rola com a lista, sem estourar',
      (tester) async {
    await _pump(
      tester,
      [_student('Ana Alves')],
      isOwner: true,
      size: const Size(900, 220),
    );

    await tester.scrollUntilVisible(
      find.text('Ana Alves'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Ana Alves'), findsOneWidget);
  });
}
