import 'memory_workout_store.dart';
import 'workout_local_store.dart';

/// Store da web — em memória. O porquê está em [MemoryWorkoutStore].
WorkoutLocalStore openWorkoutStore() => MemoryWorkoutStore();
