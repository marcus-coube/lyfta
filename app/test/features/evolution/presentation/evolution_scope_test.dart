import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/features/evolution/data/evolution_repository.dart';
import 'package:lyfta/features/evolution/domain/bioimpedance.dart';
import 'package:lyfta/features/evolution/domain/evolution_scope.dart';
import 'package:lyfta/features/evolution/domain/evolution_summary.dart';
import 'package:lyfta/features/evolution/domain/exercise_history.dart';
import 'package:lyfta/features/evolution/domain/measurement.dart';
import 'package:lyfta/features/evolution/domain/progress_photo.dart';
import 'package:lyfta/features/evolution/presentation/evolution_screen.dart';
import 'package:lyfta/features/evolution/widgets/summary_card.dart';

/// Repositório de mentira que anota o escopo de cada chamada — é o que o
/// teste precisa afirmar: a mesma tela, montada com escopos diferentes,
/// bate na porta `/me` ou na `/students/{id}` sem duplicar código (P2.5).
class _FakeRepository extends EvolutionRepository {
  _FakeRepository() : super(workoutDio: Dio(), assessmentDio: Dio());

  final scopes = <EvolutionScope>{};
  var summaryCalls = 0;

  @override
  Future<List<LoggedExercise>> loggedExercises(EvolutionScope scope) async {
    scopes.add(scope);
    return const [];
  }

  @override
  Future<EvolutionPage<BodyMeasurement>> listMeasurements(
    EvolutionScope scope, {
    String? cursor,
    int? limit,
  }) async {
    scopes.add(scope);
    return const EvolutionPage(items: []);
  }

  @override
  Future<EvolutionPage<BioimpedanceRecord>> listBioimpedance(
    EvolutionScope scope, {
    String? cursor,
    int? limit,
  }) async {
    scopes.add(scope);
    return const EvolutionPage(items: []);
  }

  @override
  Future<EvolutionPage<ProgressPhoto>> listPhotos(
    EvolutionScope scope, {
    String? cursor,
    int? limit,
  }) async {
    scopes.add(scope);
    return const EvolutionPage(items: []);
  }

  @override
  Future<EvolutionSummary> summary(EvolutionScope scope) async {
    scopes.add(scope);
    summaryCalls++;
    return const EvolutionSummary(
      photoCount: 3,
      deltas: EvolutionSummaryDeltas(),
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  EvolutionScope scope,
  _FakeRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        evolutionRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: LyTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: EvolutionScreen(scope: scope)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('escopo do aluno: 3 abas, sem Resumo — não existe /me/summary',
      (tester) async {
    final repository = _FakeRepository();
    await _pump(tester, const EvolutionScope.me(), repository);

    expect(find.byType(Tab), findsNWidgets(3));
    expect(find.byType(SummaryCard), findsNothing);
    expect(repository.summaryCalls, 0);
    expect(repository.scopes, {const EvolutionScope.me()});
  });

  testWidgets('escopo do coach: entra a aba Resumo e as chamadas levam o aluno',
      (tester) async {
    const scope = EvolutionScope.student('aluno-1');
    final repository = _FakeRepository();
    await _pump(tester, scope, repository);

    expect(find.byType(Tab), findsNWidgets(4));
    expect(find.byType(SummaryCard), findsOneWidget);
    expect(repository.summaryCalls, 1);
    // Nenhuma chamada vazou para `/me` — é o ponto do escopo.
    expect(repository.scopes, {scope});
    expect(find.text('3'), findsOneWidget);
  });
}
