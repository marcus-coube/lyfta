import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/http/api_exception.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/builder/data/plan_repository.dart';
import 'package:lyfta/features/builder/presentation/plan_builder_screen.dart';
import 'package:lyfta/shared/domain/plan.dart';

class _FakePlans extends PlanRepository {
  _FakePlans(this.plan) : super(Dio());

  Plan plan;
  final activated = <String>[];
  var saves = 0;
  Object? saveError;

  @override
  Future<Plan> byId(String id, {String? version}) async => plan;

  @override
  Future<Plan> saveDraft({
    required String planId,
    required String title,
    required List<WorkoutDay> days,
    String? description,
  }) async {
    saves++;
    if (saveError != null) throw saveError!;
    return plan;
  }

  @override
  Future<void> activate({
    required String studentId,
    required String planId,
  }) async {
    activated.add(planId);
    plan = Plan(
      id: plan.id,
      studentId: plan.studentId,
      title: plan.title,
      status: 'published',
      days: plan.days,
      versions: plan.versions,
      version: plan.version,
    );
  }
}

Plan _plan({
  String status = 'archived',
  String kind = 'assigned',
  bool published = true,
}) =>
    Plan(
      id: 'p1',
      studentId: kind == 'template' ? '' : 's1',
      title: 'Treino A/B',
      status: status,
      kind: kind,
      description: 'Descrição do modelo',
      days: [WorkoutDay(label: 'A')],
      versions: [
        PlanVersionRef(id: 'v1', versionNo: 1, isDraft: !published),
      ],
      version: PlanVersionRef(id: 'v1', versionNo: 1, isDraft: !published),
    );

Future<_FakePlans> _pump(WidgetTester tester, Plan plan) async {
  final fake = _FakePlans(plan);
  tester.view.physicalSize = const Size(700, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [planRepositoryProvider.overrideWithValue(fake)],
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
  testWidgets(
      'plano arquivado abre em leitura: sem salvar/publicar, com Ativar',
      (tester) async {
    final fake = await _pump(tester, _plan());

    expect(find.byKey(const Key('builder_read_only_banner')), findsOneWidget);
    expect(find.text('Publicar'), findsNothing);
    expect(find.text('Adicionar bloco'), findsOneWidget);
    expect(find.byKey(const Key('builder_duplicate')), findsOneWidget);

    await tester.tap(find.byKey(const Key('builder_activate')));
    await tester.pumpAndSettle();

    expect(fake.activated, ['p1']);
    // Depois de ativar o plano volta a ser editável.
    expect(find.byKey(const Key('builder_read_only_banner')), findsNothing);
    expect(find.text('Publicar'), findsOneWidget);
  });

  testWidgets('arquivado nunca publicado só oferece duplicar', (tester) async {
    await _pump(tester, _plan(published: false));

    expect(find.byKey(const Key('builder_activate')), findsNothing);
    expect(find.byKey(const Key('builder_duplicate')), findsOneWidget);
  });

  testWidgets('409 plan_archived ao salvar vira mensagem e modo leitura',
      (tester) async {
    final fake = await _pump(tester, _plan(status: 'published'));
    expect(find.byKey(const Key('builder_read_only_banner')), findsNothing);

    // O coach edita; enquanto isso o plano foi arquivado em outra tela.
    await tester.tap(find.text('Adicionar bloco'));
    await tester.pump();
    fake
      ..saveError = const ApiException(code: 'plan_archived', statusCode: 409)
      ..plan = _plan();
    await tester.tap(find.text('Salvar rascunho'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('está arquivado e não pode ser editado'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('builder_read_only_banner')), findsOneWidget);
  });

  testWidgets('modelo mostra título e descrição editáveis', (tester) async {
    await _pump(
        tester, _plan(status: 'draft', kind: 'template', published: false),);

    expect(find.byKey(const Key('template_title')), findsOneWidget);
    expect(find.text('Descrição do modelo'), findsOneWidget);
    // Modelo não tem "Salvar como modelo".
    expect(find.byKey(const Key('builder_menu')), findsNothing);
  });
}
