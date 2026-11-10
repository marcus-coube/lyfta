import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/builder/data/plan_repository.dart';
import 'package:lyfta/features/builder/presentation/plan_builder_screen.dart';
import 'package:lyfta/features/profile/domain/student_profile.dart';
import 'package:lyfta/features/profile/presentation/profile_controller.dart';
import 'package:lyfta/shared/domain/exercise.dart';
import 'package:lyfta/shared/domain/plan.dart';

BlockExercise _item(String name) => BlockExercise(
      exerciseId: 'e1',
      exercise: Exercise(
        id: 'e1',
        name: name,
        primaryMuscle: 'chest',
        equipment: 'barbell',
        level: 'beginner',
        isGlobal: true,
        status: 'active',
      ),
      sets: [PrescribedSet(repsMin: 8, repsMax: 12, restSeconds: 60)],
    );

class _FakePlans extends PlanRepository {
  _FakePlans(this.plan) : super(Dio());

  Plan plan;
  List<WorkoutDay>? saved;
  final versionsRequested = <String?>[];

  @override
  Future<Plan> byId(String id, {String? version}) async {
    versionsRequested.add(version);
    if (version == '1') {
      return Plan(
        id: plan.id,
        studentId: plan.studentId,
        title: plan.title,
        status: plan.status,
        days: [
          WorkoutDay(label: 'A', title: 'Antigo', blocks: [Block()]),
        ],
        versions: plan.versions,
        version: const PlanVersionRef(id: 'v1', versionNo: 1, isDraft: false),
      );
    }
    return plan;
  }

  @override
  Future<List<PlanVersionSummary>> versions(String planId) async => [
        const PlanVersionSummary(
          versionNo: 2,
          isDraft: true,
          daysCount: 2,
          exercisesCount: 3,
        ),
        PlanVersionSummary(
          versionNo: 1,
          isDraft: false,
          daysCount: 1,
          exercisesCount: 1,
          publishedAt: DateTime(2026, 11, 1),
        ),
      ];

  @override
  Future<Plan> saveDraft({
    required String planId,
    required String title,
    required List<WorkoutDay> days,
    String? description,
  }) async {
    saved = [for (final d in days) d.copy(label: d.label)];
    return plan;
  }
}

Plan _plan({bool draft = false}) => Plan(
      id: 'p1',
      studentId: 's1',
      title: 'Treino',
      status: 'published',
      days: [
        WorkoutDay(
          label: 'A',
          title: 'Peito',
          blocks: [
            Block(exercises: [_item('Supino')]),
            Block(exercises: [_item('Crucifixo')]),
          ],
        ),
        WorkoutDay(label: 'B', title: 'Costas'),
      ],
      versions: [
        const PlanVersionRef(id: 'v1', versionNo: 1, isDraft: false),
        if (draft) const PlanVersionRef(id: 'v2', versionNo: 2, isDraft: true),
      ],
      version: draft
          ? const PlanVersionRef(id: 'v2', versionNo: 2, isDraft: true)
          : const PlanVersionRef(id: 'v1', versionNo: 1, isDraft: false),
    );

Future<_FakePlans> _pump(
  WidgetTester tester,
  Plan plan, {
  List<Injury> injuries = const [],
  double width = 1100,
}) async {
  final fake = _FakePlans(plan);
  // A fonte de teste (Ahem) estoura o "Adicionar dia" da lista lateral de 240
  // px: artefato de teste (Notas da P6.3), não do layout real.
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
  tester.view.physicalSize = Size(width, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        planRepositoryProvider.overrideWithValue(fake),
        injuriesProvider.overrideWith((ref, scope) async => injuries),
      ],
      child: MaterialApp(
        theme: LyTheme.dark(),
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const PlanBuilderScreen(planId: 'p1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('arrastar a alça reordena os blocos e o salvar envia a nova ordem',
      (tester) async {
    final fake = await _pump(tester, _plan());
    expect(find.byKey(const Key('builder_unpublished_banner')), findsNothing);

    final first = tester.getTopLeft(find.text('Supino')).dy;
    final second = tester.getTopLeft(find.text('Crucifixo')).dy;
    expect(first, lessThan(second));

    // Alça do 1º bloco (a 1ª da tela, a do dia fica na lista lateral).
    final handle = find.byIcon(Icons.drag_indicator).at(2);
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, 25));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Crucifixo')).dy,
      lessThan(tester.getTopLeft(find.text('Supino')).dy),
    );
    // Mexeu no plano: o aviso aparece e o salvar manda a ordem nova.
    expect(find.byKey(const Key('builder_unpublished_banner')), findsOneWidget);
    await tester.tap(find.text('Salvar rascunho'));
    await tester.pumpAndSettle();
    final names = fake.saved!.first.blocks
        .map((b) => b.exercises.single.exercise!.name)
        .toList();
    expect(names, ['Crucifixo', 'Supino']);
  });

  testWidgets('arrastar a alça do exercício reordena dentro do bloco',
      (tester) async {
    final fake = await _pump(
      tester,
      Plan(
        id: 'p1',
        studentId: 's1',
        title: 'Treino',
        status: 'published',
        days: [
          WorkoutDay(
            label: 'A',
            blocks: [
              Block(exercises: [_item('Supino'), _item('Crucifixo')]),
            ],
          ),
        ],
        versions: const [PlanVersionRef(id: 'v1', versionNo: 1, isDraft: false)],
        version: const PlanVersionRef(id: 'v1', versionNo: 1, isDraft: false),
      ),
    );
    // Alça na mesma altura do nome do 2º exercício.
    final target = tester.getCenter(find.text('Crucifixo')).dy;
    final handles = find.byIcon(Icons.drag_indicator).evaluate().toList();
    final handle = handles
        .map((e) => tester.getCenter(find.byWidget(e.widget)))
        .reduce((a, b) => (a.dy - target).abs() < (b.dy - target).abs() ? a : b);
    // Mouse (web/desktop): a alça arrasta sem long-press, em saltos grandes.
    final gesture =
        await tester.startGesture(handle, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, -150));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, -5));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Crucifixo')).dy,
      lessThan(tester.getTopLeft(find.text('Supino')).dy),
    );
    await tester.tap(find.text('Salvar rascunho'));
    await tester.pumpAndSettle();
    expect(
      fake.saved!.first.blocks.single.exercises.map((e) => e.exercise!.name),
      ['Crucifixo', 'Supino'],
    );
  });

  testWidgets('arrastar dias na lista lateral reordena e mantém o aberto',
      (tester) async {
    final fake = await _pump(tester, _plan());

    await tester.drag(
      find.byIcon(Icons.drag_indicator).first,
      const Offset(0, 160),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar rascunho'));
    await tester.pumpAndSettle();

    expect(fake.saved!.map((d) => d.label).toList(), ['B', 'A']);
  });

  testWidgets('duplicar bloco e duplicar dia fazem cópia independente',
      (tester) async {
    final fake = await _pump(tester, _plan());

    await tester.tap(find.byKey(const Key('block_menu')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicar bloco'));
    await tester.pumpAndSettle();
    expect(find.text('Supino'), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicar dia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar rascunho'));
    await tester.pumpAndSettle();

    final days = fake.saved!;
    expect(days.map((d) => d.label).toList(), ['A', 'C', 'B']);
    expect(days[1].blocks.length, 3);
    expect(identical(days[0].blocks.first, days[1].blocks.first), isFalse);
  });

  testWidgets('rascunho mostra o aviso de alterações não publicadas',
      (tester) async {
    await _pump(tester, _plan(draft: true));
    expect(find.byKey(const Key('builder_unpublished_banner')), findsOneWidget);
  });

  testWidgets('histórico abre a versão publicada em leitura e volta ao atual',
      (tester) async {
    final fake = await _pump(tester, _plan(draft: true));

    await tester.tap(find.byKey(const Key('builder_history')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history_v2')), findsOneWidget);
    expect(find.textContaining('1 dia'), findsWidgets);
    await tester.tap(find.byKey(const Key('history_v1')));
    await tester.pumpAndSettle();

    expect(fake.versionsRequested, contains('1'));
    expect(
      find.byKey(const Key('builder_viewing_version_banner')),
      findsOneWidget,
    );
    expect(find.text('Publicar'), findsNothing);
    expect(find.text('Adicionar bloco'), findsNothing);
    expect(find.byKey(const Key('builder_menu')), findsNothing);
    expect(find.byKey(const Key('builder_unpublished_banner')), findsNothing);

    await tester.tap(find.byKey(const Key('builder_back_to_current')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('builder_viewing_version_banner')),
      findsNothing,
    );
    expect(find.text('Publicar'), findsOneWidget);
  });

  testWidgets('lesões ativas aparecem no topo e recolhem; resolvida não conta',
      (tester) async {
    await _pump(
      tester,
      _plan(),
      injuries: [
        Injury(
          id: 'i1',
          bodyRegion: 'knee',
          description: 'Condromalácia',
          createdAt: DateTime(2026, 10, 1),
        ),
        Injury(
          id: 'i2',
          bodyRegion: 'neck',
          description: 'Antiga',
          resolvedAt: DateTime(2026, 10, 20),
          createdAt: DateTime(2026, 9, 1),
        ),
      ],
    );

    expect(find.text('1 lesão ativa'), findsOneWidget);
    expect(find.textContaining('Condromalácia'), findsOneWidget);
    expect(find.textContaining('Antiga'), findsNothing);

    await tester.tap(find.byKey(const Key('builder_injuries_toggle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Condromalácia'), findsNothing);
    expect(find.text('1 lesão ativa'), findsOneWidget);
  });

  testWidgets('sem lesão ativa o banner não aparece', (tester) async {
    await _pump(tester, _plan());
    expect(find.byKey(const Key('builder_injuries_banner')), findsNothing);
  });

  testWidgets('layout estreito: menu do dia duplica e reordena sem a lista lateral',
      (tester) async {
    final fake = await _pump(tester, _plan(), width: 420);

    await tester.tap(find.byKey(const Key('day_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mover para baixo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar rascunho'));
    await tester.pumpAndSettle();

    expect(fake.saved!.map((d) => d.label).toList(), ['B', 'A']);
  });
}
