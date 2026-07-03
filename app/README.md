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

## Estrutura

```
lib/
  core/
    design_system/   # tokens, tema e componentes Ly* (barrel: design_system.dart)
  features/
    auth/            # login (visual)
  shared/            # (futuro) utilitários entre features
```

Guidelines: `docs/guidelines/flutter.md`.
