# Lyfta — App Flutter

App único (Android/iOS/Web) — ver `docs/000-product_description.md`.

## Rodar pela primeira vez

O repositório versiona `lib/`, `pubspec.yaml`, configs **e `android/`**
(ADR-014 — o manifest carrega permissões e o cleartext de debug). As demais
pastas de plataforma são geradas localmente:

```bash
cd app
flutter create . --project-name lyfta --org br.com.lyfta --platforms=ios,web
flutter pub get
flutter run -d chrome   # ou -d <device>
```

> **Não** passe `android` nessa lista: `flutter create` sobrescreveria os
> arquivos versionados. `flutter create .` não toca no que já existe em `lib/`.
> Confira com `git status` após rodar.

## Android (emulador ou device)

O SDK não vem com o repo. Numa máquina nova:

```bash
brew install openjdk@21                          # o Gradle do template não aceita JDK 26
brew install --cask android-commandlinetools
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
yes | sdkmanager --sdk_root="$ANDROID_HOME" --licenses
sdkmanager --sdk_root="$ANDROID_HOME" platform-tools "platforms;android-36" \
  "build-tools;36.0.0" emulator "system-images;android-36;google_apis;arm64-v8a"
flutter config --android-sdk="$ANDROID_HOME" --jdk-dir=/opt/homebrew/opt/openjdk@21
avdmanager create avd -n lyfta_pixel -k "system-images;android-36;google_apis;arm64-v8a" -d pixel_7
emulator -avd lyfta_pixel &
```

Imagem `google_apis` e não `google_apis_playstore`: só nela o `adb root`
funciona, o que permite alternar modo avião por comando no teste offline
(ADR-003).

Backend local visto de dentro do emulador é `10.0.2.2`, não `localhost`:

```bash
flutter run -d emulator-5554 \
  --dart-define=IDENTITY_BASE_URL=http://10.0.2.2:8081 \
  --dart-define=WORKOUT_BASE_URL=http://10.0.2.2:8082
```

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
