import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/design_system/design_system.dart';
import 'package:lyfta/core/http/api_exception.dart';
import 'package:lyfta/core/l10n/gen/app_localizations.dart';
import 'package:lyfta/core/realtime/comms_socket.dart';
import 'package:lyfta/core/realtime/comms_socket_provider.dart';
import 'package:lyfta/features/checkin/data/checkin_repository.dart';
import 'package:lyfta/features/checkin/domain/checkin.dart';
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
  _FakeRepository({this.measurementsError})
      : super(workoutDio: Dio(), assessmentDio: Dio());

  /// Quando presente, medidas e bioimpedância falham com este erro.
  final Object? measurementsError;

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
    if (measurementsError != null) throw measurementsError!;
    return const EvolutionPage(items: []);
  }

  @override
  Future<EvolutionPage<BioimpedanceRecord>> listBioimpedance(
    EvolutionScope scope, {
    String? cursor,
    int? limit,
  }) async {
    scopes.add(scope);
    if (measurementsError != null) throw measurementsError!;
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

/// Repositório de check-ins de mentira — a aba Check-ins (P3.5 §3) é
/// coach-only, mas não é o que este teste cobre (isso é
/// `coach_checkins_tab_test.dart`); aqui só evita bater na rede de verdade
/// quando a tela monta a aba, para o `pumpAndSettle` não depender do
/// `comms` estar no ar.
class _FakeCheckinRepository extends CheckinRepository {
  _FakeCheckinRepository() : super(Dio());

  @override
  Future<CheckinPage> list({
    required String studentId,
    String? cursor,
    int? limit,
  }) async {
    return const CheckinPage(items: []);
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
        checkinRepositoryProvider.overrideWithValue(_FakeCheckinRepository()),
        // A aba Check-ins escuta o socket do `comms` (P3.5 §3) — sem
        // sobrescrever, `commsSocketProvider` puxaria `authControllerProvider`
        // de verdade (`ref.listen` dentro dele) e bateria no secure storage
        // real, que não tem platform channel neste teste de widget.
        commsSocketProvider.overrideWithValue(
          CommsSocketService(
            readAccessToken: () async => null,
            refreshAccessToken: () async => null,
          ),
        ),
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

    // Resumo, Carga, Medidas, Fotos e Check-ins (P3.5 §3) — a quinta aba
    // coach-only.
    expect(find.byType(Tab), findsNWidgets(5));
    expect(find.byType(SummaryCard), findsOneWidget);
    expect(repository.summaryCalls, 1);
    // Nenhuma chamada vazou para `/me` — é o ponto do escopo.
    expect(repository.scopes, {scope});
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets(
      'coach sem consentimento de saúde do aluno: mensagem própria, sem repetir',
      (tester) async {
    const scope = EvolutionScope.student('aluno-1');
    final repository = _FakeRepository(
      measurementsError: const ApiException(
        code: 'consent_required',
        params: {'purpose': 'health_data'},
        statusCode: 403,
      ),
    );
    await _pump(tester, scope, repository);

    final l10n =
        AppLocalizations.of(tester.element(find.byType(EvolutionScreen)));
    await tester.tap(find.text(l10n.evolutionTabMeasurements));
    await tester.pumpAndSettle();

    expect(find.text(l10n.errorStudentConsentRequired), findsWidgets);
    expect(find.text(l10n.errorConsentRequired), findsNothing);
    expect(find.text(l10n.commonRetry), findsNothing);
  });
}
