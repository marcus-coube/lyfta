# ADR-014 — Pasta `android/` versionada; demais plataformas geradas

**Status:** Aceito
**Data:** 2026-09-01

## Contexto

Até aqui `app/` versionava só `lib/`, `pubspec.yaml` e configs: as pastas de
plataforma nasciam de `flutter create .` em cada máquina (app/README.md). O
arranjo funcionou enquanto o alvo exercitado era a web.

Ao configurar o Android no Mac (pré-requisito do P1.8, que pede o roteiro E2E
com o aluno em Android), três ajustes se mostraram **obrigatórios e permanentes**,
os três dentro de `android/`:

1. **`VIBRATE` e `POST_NOTIFICATIONS`** no manifest — sem eles o timer de
   descanso do P1.7 não vibra nem avisa em segundo plano. O manifest do template
   não traz nenhuma das duas.
2. **Cleartext HTTP em debug** — `targetSdk` 36 recusa HTTP em claro, e os
   serviços locais (8081/8082) falam HTTP puro em dev. Sem um
   `network_security_config.xml` o app no emulador não alcança o backend.
3. **Core library desugaring** no `build.gradle.kts` — `flutter_local_notifications`
   não monta sem ele (`checkDebugAarMetadata` falha).

Nenhum sobrevive a um `flutter create .`, e nenhum viaja para a outra máquina.
Refazer os três à mão a cada clone é erro silencioso esperando acontecer: o app
compila e roda, só que sem notificação e sem rede.

## Decisão

1. **`app/android/` entra no git.** Ficam de fora apenas artefatos e o que é da
   máquina — `local.properties`, `gradlew`, `.gradle/`, `build/`, keystores —
   o `android/.gitignore` do próprio template já cobre a maior parte.
2. **`ios/`, `web/`, `macos/`, `linux/`, `windows/` seguem geradas** por
   `flutter create .`. Cada uma entra no git **quando** precisar de configuração
   que não sobreviva à regeração — e aí basta uma linha no `.gitignore`, sem
   novo ADR. O gatilho é este: *o alvo exige edição manual permanente?*
3. **Cleartext é exclusividade do source set de `debug`** e nominal
   (`10.0.2.2`, `localhost`, `127.0.0.1`). Release continua HTTPS-only —
   `10.0.2.2` é o host visto de dentro do emulador; `localhost` cobre o
   `adb reverse` em device físico.
4. **`SCHEDULE_EXACT_ALARM` é declarada, mas opcional.** Negada, o
   `RestTimerService` já cai para `inexactAllowWhileIdle` (P1.7): descanso
   avisado com atraso de segundos é melhor que descanso sem aviso.

## Consequências

- O manifest do Android vira **fonte de verdade versionada**: permissão nova de
  plataforma é revisada em diff, não redescoberta por bug em produção.
- `flutter create .` deixa de ser idempotente para o Android — rodá-lo de novo
  sobrescreve os arquivos versionados. O `app/README.md` passa a mandar rodar
  `flutter create` **sem** `android` na lista de plataformas.
- ~20 arquivos gerados entram no repositório. É o preço de um alvo que precisa
  de configuração de verdade, e o mesmo que a maioria dos projetos Flutter paga.
- Atualização de Flutter que mude o template Android vira trabalho manual
  (comparar com um `flutter create` em pasta temporária). Aceito: acontece
  raramente e a alternativa é perder as três correções toda vez.
