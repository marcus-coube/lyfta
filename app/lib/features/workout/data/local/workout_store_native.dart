import 'package:drift_flutter/drift_flutter.dart';

import 'workout_database.dart';
import 'workout_local_store.dart';

/// Store persistente (mobile/desktop): SQLite via Drift no diretório de
/// dados do app (ADR-003 §3). O arquivo sobrevive a fechar o app, que é o
/// requisito real — treinar em modo avião e sincronizar depois.
WorkoutLocalStore openWorkoutStore() {
  return DriftWorkoutStore(
    WorkoutDatabase(driftDatabase(name: 'lyfta_workout')),
  );
}
