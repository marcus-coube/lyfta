# Lyfta — App Flutter

App único (Android/iOS/Web) — ver `docs/000-product_description.md`.

## Rodar pela primeira vez

O repositório versiona apenas `lib/`, `pubspec.yaml` e configs. Gere as
pastas de plataforma localmente:

```bash
cd app
flutter create . --project-name lyfta --org br.com.lyfta --platforms=android,ios,web
flutter pub get
flutter run -d chrome   # ou -d <device>
```

> `flutter create .` não sobrescreve os arquivos existentes de `lib/`.
> Confira com `git status` após rodar.

## Banco local (drift)

A execução de treino é offline-first (ADR-003): o banco local vive em
`lib/features/workout/data/local/`. Mexeu nas tabelas → regerar:

```bash
dart run build_runner build
```

O arquivo gerado (`workout_database.g.dart`) é versionado, então o CI não roda
codegen. Em mobile/desktop o store é SQLite; **na web é em memória** (o drift
na web precisaria de `sqlite3.wasm` e `drift_worker.js` dentro de `web/`, que
não é versionada) — o porquê está em `MemoryWorkoutStore` e nas notas do P1.7.

## Estrutura

```
lib/
  core/
    design_system/   # tokens, tema e componentes Ly* (barrel: design_system.dart)
  shared/            # domínio, widgets e rótulos usados por 2+ features
  features/
    auth/ library/ builder/ students/   # professor
    workout/                            # aluno: treino do dia + execução
```

Guidelines: `docs/guidelines/flutter.md`.
