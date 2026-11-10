import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/http/api_exception.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/evolution/domain/evolution_scope.dart';
import 'package:lyfta/features/profile/data/profile_repository.dart';
import 'package:lyfta/features/profile/domain/student_profile.dart';
import 'package:lyfta/features/profile/presentation/health_section.dart';

class _FakeProfiles extends ProfileRepository {
  _FakeProfiles({this.error}) : super(Dio());

  StudentProfile profileValue = const StudentProfile(
    goal: 'strength',
    weeklyTarget: 4,
    medicalNotes: 'Asma',
  );
  final ApiException? error;
  final saved = <(EvolutionScope, StudentProfile)>[];
  final injuryList = <Injury>[
    Injury(
      id: 'i1',
      bodyRegion: 'knee',
      description: 'Condromalácia',
      createdAt: DateTime(2026, 10, 1),
    ),
  ];
  final added = <InjuryInput>[];
  final resolved = <(String, DateTime?)>[];
  final deleted = <String>[];

  @override
  Future<StudentProfile> profile(EvolutionScope scope) async {
    if (error != null) throw error!;
    return profileValue;
  }

  @override
  Future<StudentProfile> saveProfile(
    EvolutionScope scope,
    StudentProfile profile,
  ) async {
    saved.add((scope, profile));
    profileValue = profile;
    return profile;
  }

  @override
  Future<List<Injury>> injuries(EvolutionScope scope) async => [...injuryList];

  @override
  Future<Injury> addInjury(EvolutionScope scope, InjuryInput input) async {
    added.add(input);
    final injury = Injury(
      id: 'i${injuryList.length + 1}',
      bodyRegion: input.bodyRegion,
      description: input.description,
      since: input.since,
      createdAt: DateTime(2026, 11, 9),
    );
    injuryList.add(injury);
    return injury;
  }

  @override
  Future<Injury> setResolved(
    EvolutionScope scope,
    String injuryId,
    DateTime? resolvedAt,
  ) async {
    resolved.add((injuryId, resolvedAt));
    final i = injuryList.indexWhere((e) => e.id == injuryId);
    final old = injuryList[i];
    injuryList[i] = Injury(
      id: old.id,
      bodyRegion: old.bodyRegion,
      description: old.description,
      since: old.since,
      resolvedAt: resolvedAt,
      createdAt: old.createdAt,
    );
    return injuryList[i];
  }

  @override
  Future<void> deleteInjury(EvolutionScope scope, String injuryId) async {
    deleted.add(injuryId);
    injuryList.removeWhere((e) => e.id == injuryId);
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeProfiles fake,
  EvolutionScope scope,
) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [profileRepositoryProvider.overrideWithValue(fake)],
      child: MaterialApp(
        theme: LyTheme.dark(),
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(child: HealthSection(scope: scope)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('coach edita notas privadas e salva o perfil inteiro',
      (tester) async {
    final fake = _FakeProfiles();
    await _pump(tester, fake, const EvolutionScope.student('aluno-1'));

    expect(find.text('Asma'), findsOneWidget);
    expect(find.byKey(const Key('profile_coach_notes')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('profile_coach_notes')),
      'Cuidado com o ombro',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('profile_health_save')));
    await tester.pumpAndSettle();

    expect(fake.saved, hasLength(1));
    final sent = fake.saved.single.$2;
    expect(sent.coachNotes, 'Cuidado com o ombro');
    // Campos que a tela não mexeu seguem como foram lidos.
    expect(sent.goal, 'strength');
    expect(sent.weeklyTarget, 4);
    expect(sent.medicalNotes, 'Asma');
    expect(find.text('Objetivo e saúde salvos.'), findsOneWidget);
  });

  testWidgets(
      'aluno: sem notas do coach, meta semanal só leitura, lesões editáveis',
      (tester) async {
    final fake = _FakeProfiles();
    await _pump(tester, fake, const EvolutionScope.me());

    expect(find.byKey(const Key('profile_coach_notes')), findsNothing);
    expect(find.text('Asma'), findsOneWidget);
    // Meta semanal é do coach: o aluno lê, não escolhe.
    expect(find.byKey(const Key('profile_weekly_target')), findsNothing);
    expect(
      find.byKey(const Key('profile_weekly_target_readonly')),
      findsOneWidget,
    );
    expect(find.text('4 treinos por semana'), findsOneWidget);
    expect(find.text('Definida pelo seu professor.'), findsOneWidget);
    // Lesões: o aluno vê e pode adicionar.
    expect(find.text('Condromalácia'), findsOneWidget);
    expect(find.byKey(const Key('injury_add')), findsOneWidget);
  });

  testWidgets('adiciona, resolve e remove lesão', (tester) async {
    final fake = _FakeProfiles();
    await _pump(tester, fake, const EvolutionScope.student('aluno-1'));

    expect(find.text('Condromalácia'), findsOneWidget);

    // Nova lesão.
    await tester.tap(find.byKey(const Key('injury_add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('injury_region')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ombro').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('injury_description')),
      'Tendinite',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('injury_save')));
    await tester.pumpAndSettle();
    expect(fake.added.single.bodyRegion, 'shoulder');
    expect(fake.added.single.description, 'Tendinite');
    expect(find.text('Tendinite'), findsOneWidget);

    // Resolve a primeira: vai para "Resolvidas".
    await tester.tap(find.byKey(const Key('injury_menu_i1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marcar como resolvida'));
    await tester.pumpAndSettle();
    expect(fake.resolved.single.$1, 'i1');
    expect(fake.resolved.single.$2, isNotNull);
    expect(find.text('Resolvidas'), findsOneWidget);

    // Remove, com confirmação.
    await tester.tap(find.byKey(const Key('injury_menu_i1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remover').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('injury_delete_confirm')));
    await tester.pumpAndSettle();
    expect(fake.deleted, ['i1']);
    expect(find.text('Condromalácia'), findsNothing);
  });

  testWidgets('formulário de lesão só salva com região e descrição',
      (tester) async {
    final fake = _FakeProfiles();
    await _pump(tester, fake, const EvolutionScope.student('aluno-1'));

    await tester.tap(find.byKey(const Key('injury_add')));
    await tester.pumpAndSettle();

    TextButton save() =>
        tester.widget<TextButton>(find.byKey(const Key('injury_save')));
    expect(save().onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('injury_description')),
      'Dor ao agachar',
    );
    await tester.pump();
    expect(save().onPressed, isNull); // falta a região

    await tester.tap(find.byKey(const Key('injury_region')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lombar').last);
    await tester.pumpAndSettle();
    expect(save().onPressed, isNotNull);
  });

  testWidgets(
      'coach: aluno sem consentimento de saúde vê a mensagem do aluno, sem repetir',
      (tester) async {
    final fake = _FakeProfiles(
      error: const ApiException(code: 'consent_required', statusCode: 403),
    );
    await _pump(tester, fake, const EvolutionScope.student('aluno-1'));

    expect(find.textContaining('O aluno não autorizou'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsNothing);
  });
}
