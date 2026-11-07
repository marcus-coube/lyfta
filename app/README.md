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

`TERMS_VERSION` (`--dart-define=TERMS_VERSION=...`, padrão `2026-11-v1`) é a
versão dos termos de uso e da política de privacidade em `assets/legal/`
(ADR-008 §6). Tem de ser a mesma do `TERMS_VERSION` do `identity` e a que consta
dentro de cada texto (um teste confere); o backend recusa o aceite com outra
versão. Mudar a versão obriga todo usuário a consentir de novo.

## iOS (simulador, Mac)

Exige Xcode completo (não só Command Line Tools), CocoaPods
(`brew install cocoapods`) e terminal em UTF-8 (`export LANG=en_US.UTF-8`, senão
o `pod` reclama). Validado com Xcode 27.2 + runtime iOS 27.2, macOS 27.2,
Flutter 3.44.4.

Depois do `flutter create` da receita acima, dois ajustes **locais** (a pasta
`ios/` não é versionada — refazer sempre que ela for recriada):

1. **Mínimo iOS 15** — o Firebase exige e o Xcode 27 não aceita menos. Em
   `ios/Runner.xcodeproj/project.pbxproj`, as três ocorrências de
   `IPHONEOS_DEPLOYMENT_TARGET = 13.0;` viram `15.0`. No `ios/Podfile`,
   descomentar `platform :ios, '15.0'` e forçar o mesmo nos pods:

   ```ruby
   post_install do |installer|
     installer.pods_project.targets.each do |target|
       flutter_additional_ios_build_settings(target)
       target.build_configurations.each do |config|
         config.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] = "15.0"
       end
     end
   end
   ```

2. **Apagar `test/widget_test.dart`** — o `flutter create` gera o teste de
   contador do template, que quebra o `flutter test` (não existe `MyApp`).

Rodar **num simulador específico**, não com build genérico:

```bash
xcrun simctl list devices available        # pegar o UDID
flutter run -d <UDID>
```

`flutter build ios --simulator` falha no Xcode 27: o `lipo -verify_arch` passou
a aceitar uma arquitetura só, e o Flutter 3.44 passa `arm64 x86_64`. O
`flutter run -d <UDID>` compila só a arquitetura do aparelho e passa. Plugins
como `connectivity_plus` e `device_info_plus` já usam APIs do SDK iOS 26 —
Xcode ≤ 16 não compila o projeto.

O simulador usa a rede do Mac: `localhost` funciona direto, sem
`--dart-define` (diferente do `10.0.2.2` do Android). No Xcode 27 o app
Simulator virou **DeviceHub** (`Xcode.app/Contents/Applications/`). O app
segue o idioma do aparelho; para pt-BR:

```bash
xcrun simctl spawn booted defaults write -g AppleLanguages -array pt-BR en-BR
```

Push no iOS ainda não está configurado (falta o `GoogleService-Info.plist` e a
chave APNs no Firebase); o app tolera a ausência e roda sem push.

## Relato de erros (Sentry/GlitchTip, P4.6)

Desligado por padrão: com `SENTRY_DSN` vazio (dev e CI) nada sai do aparelho e
o erro só aparece no console. Para ligar:

```
flutter run -d chrome \
  --dart-define=SENTRY_DSN=https://<chave>@<host>/<projeto> \
  --dart-define=SENTRY_ENVIRONMENT=production \
  --dart-define=APP_RELEASE=1.0.0+1
```

`APP_RELEASE` deve repetir o `version:` do `pubspec.yaml`. O evento leva só
`user_id`/`tenant_id` (ADR-008); filtro em `lib/core/observability/`.

## Firebase (push, P3.4/P3.5)

Projeto de dev: **`lyfta-a3bd3`**. O app Android é registrado lá com o package
`br.com.lyfta.lyfta` e o `google-services.json` fica **versionado** em
`android/app/` — junto do resto do `android/` (ADR-014). Ele não é segredo de
servidor: traz a API key do Android, restrita por package + assinatura. O
segredo de verdade é a service account do Admin SDK, que vive só no
`backend/comms/.env` (`FCM_CREDENTIALS_JSON`), nunca no git.

Push exige emulador com **Play Services**. A AVD da receita acima usa
`google_apis` (sem Play Store) para permitir `adb root` no teste offline — para
testar push, crie uma segunda AVD com `google_apis_playstore`, ou use um
aparelho físico.

O plugin `com.google.gms.google-services` (P3.5) está declarado em
`android/settings.gradle.kts` e só é aplicado em `android/app/build.gradle.kts`
**se o `google-services.json` existir**. Sem o arquivo o build segue, com um
aviso, e o app roda sem push (pós-MVP em emulador; baixar o arquivo é a
pendência pré-loja L1 do STATUS). `minSdk` é 26 (Android 8.0), exigência do
`sentry_flutter`.

> **`applicationId` é provisório (ADR-015).** `br.com.lyfta.lyfta` só pode mudar
> **antes** do primeiro upload em loja: o Play Console reserva o package na conta para
> sempre (mesmo apagando o rascunho) e o bundle ID no App Store Connect idem.
> Validar APK/IPA com o cliente por fora da loja (link direto, Firebase App
> Distribution, ad-hoc) **não** queima o nome — e é assim que o cliente valida,
> antes de qualquer loja. Trocar depois custa: as duas
> linhas de `android/app/build.gradle.kts`, o pacote/pasta do `MainActivity.kt`,
> a receita de `flutter create` acima, um app novo no mesmo projeto Firebase
> (com `google-services.json` novo) e os tokens FCM já registrados, que morrem
> na reinstalação.

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
    realtime/         # CommsSocketService — WS único do `comms`, chat + check-ins
    push/             # FCM: permissão, registro de token, deep link (P3.5)
  shared/            # domínio, widgets e rótulos usados por 2+ features
  features/
    auth/ library/ builder/ students/   # professor
    workout/                            # aluno: treino do dia + execução
    evolution/                          # aluno e professor: gráfico, medidas, fotos
    chat/ checkin/                      # aluno e professor: conversa e avaliação de treino
```

Guidelines: `docs/guidelines/flutter.md`.
