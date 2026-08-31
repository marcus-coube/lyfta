export 'workout_local_store.dart';
// A escolha do storage é por plataforma, não por tela: SQLite onde há
// sistema de arquivos, memória na web (ver `MemoryWorkoutStore`).
export 'workout_store_native.dart'
    if (dart.library.js_interop) 'workout_store_web.dart';
