# P12 — Mídia de execução e release 2.5

Meta da fase: o aluno anexa vídeo ou foto durante o treino para o professor
avaliar o movimento; a mídia é apagada 7 dias depois que o professor a vê ou
responde, e o aluno é avisado disso ao anexar.

O que já existe: presign por serviço (PUT de 15 min com tipo e tamanho na
assinatura), bucket único, imagem do chat no comms (15 MB), `image_picker`,
`video_player`, job diário do comms, exclusão LGPD do comms
(`DELETE /internal/v1/users/{id}`). **Não existe** exclusão física de objeto no
comms nem job de expiração em serviço algum.

Dono: `comms` — é onde vivem o check-in (mesma chave `session_client_id`), o
estado de revisão, o chat e o push.

Refs normativas: ADR-003, ADR-008, ADR-016, [ADR-020](../../adr/ADR-020-midia-de-execucao-retencao.md).

---

## - [x] P12.1 Mídia de execução (comms)

**Objetivo:** upload, leitura, ciência do professor e expiração.
**Decisões:** D5, D6, D7.
**Passos:**
1. Migration `0008_session_media`: `session_media` (`id`, `tenant_id`,
   `student_id`, `session_client_id`, `exercise_id NULL`, `exercise_name NULL`
   (copiado, sem FK entre bancos), `media_key`, `content_type`, `size_bytes`,
   `note` até 280, `created_at`, `acked_by`, `acked_at`, `delete_after`,
   `deleted_at`), RLS, índices `(tenant_id, student_id, created_at DESC)` e
   parcial em `delete_after WHERE deleted_at IS NULL`. No insert,
   `delete_after = created_at + 30 dias` (D5).
2. Aluno: `POST /v1/me/session-media/presign` `{session_client_id,
   content_type, size_bytes}` — tipos `video/mp4`, `video/quicktime`,
   `video/webm`, `image/jpeg|png|webp`; **máx. 20 MB**; chave
   `tenants/{t}/students/{s}/session-media/{session_client_id}/{uuid}.{ext}`.
   `POST /v1/me/session-media` `{session_client_id, media_key, exercise_id?,
   exercise_name?, note?}` (valida prefixo da chave e confere tamanho/tipo com
   `HEAD` no objeto; máx. 3 por sessão = 422 `session_media_limit`).
   `GET /v1/me/session-media?session_client_id=`, `DELETE /v1/me/session-media/{id}`
   (o aluno pode retirar; apaga o objeto na hora).
   Exige a finalidade `progress_photos` nas claims (D6; 403 no padrão do
   assessment).
3. Coach (vínculo via `coachlink`): `GET /v1/session-media?student_id=&pending=`
   (cursor; itens com URL de leitura assinada curta, nunca pública),
   `POST /v1/session-media/{id}/ack` `{feedback?}` — grava `acked_by/at`
   **uma vez** (idempotente; repetir não renova o prazo) e
   `delete_after = LEAST(delete_after, acked_at + 7 dias)`. Com `feedback`
   (D7), o servidor publica uma mensagem de texto no chat direto coach↔aluno
   (cria a conversa se não existir) citando treino/exercício — WS e push pelo
   caminho normal do chat. Owner pode dar ciência.
4. Push ao professor vinculado quando chega mídia nova (payload abre a ficha
   na aba Check-ins). `GET /v1/checkins/stats` ganha `unacked_media`.
5. Expiração: no tick do job do comms (com o lock que ele já usa), apagar o
   objeto no S3 e marcar `deleted_at` de tudo com `delete_after <= now()`;
   falha no S3 não marca (tenta de novo no próximo tick). A linha fica (some a
   chave), para o histórico "mídia expirada". Relógio injetável.
6. `media.Presigner` do comms ganha `DeleteObject` e `DeleteStudentObjects`
   (duplicar do assessment, ADR-013). Exclusão de conta (`erasure.go`): apaga
   fisicamente objetos e linhas de `session_media` do aluno.
7. Texto dos termos (`app/assets/legal/`, 3 idiomas): mídia de execução dentro
   de `progress_photos`, com a regra de retenção; `TERMS_VERSION` novo no
   identity e no app (revisão jurídica segue na lista pré-loja, L6).
**Aceite:** presign de 21 MB = 422; 4ª mídia da sessão = 422; ack define
`delete_after` em 7 dias e o segundo ack não muda; job apaga objeto e marca
`deleted_at` (teste com relógio falso, incluindo o teto de 30 dias sem ack);
feedback vira mensagem no chat do aluno; coach fora do vínculo = 404; exclusão
de conta remove objetos; teste de isolamento cross-tenant.

## - [x] P12.2 App — anexar mídia no treino (Flutter, aluno)

**Objetivo:** gravar ou escolher mídia sem sair do player.
**Decisão:** D4.
**Passos:**
1. Ação "Enviar vídeo ao professor" no cartão do exercício e no menu do player
   (sem exercício). Folha com câmera/galeria, vídeo ou foto, observação
   opcional (280).
2. **Aviso obrigatório antes de enviar** (i18n): limite de 20 MB e "apagado
   7 dias depois que seu professor visualizar ou responder (ou em 30 dias)".
3. Vídeo no celular: `image_picker.pickVideo` com `maxDuration` de 60 s e
   compressão para MP4 com `video_compress` (dependência nova — só com D4
   aprovada; registrar no `pubspec` e no README do app). Foto: mesma compressão
   das fotos de progresso. Passou de 20 MB depois de comprimir → mensagem com o
   tamanho, nada é enviado. Web: sem compressão, só a validação.
4. Upload com progresso e cancelar, sem bloquear o registro de séries (o treino
   continua). **Exige rede** (ADR-020): offline, a ação explica que precisa de
   conexão; falha no meio = "tentar de novo" enquanto a sessão estiver aberta.
   Não entra na fila do ADR-003.
5. Sem consentimento `progress_photos`: a ação leva à tela de privacidade da
   Conta em vez de abrir a câmera.
6. Lista "Enviados neste treino" no player (miniatura, estado: enviado / visto
   pelo professor / expira em DD/MM) com remover. Permissões de câmera/microfone
   no `AndroidManifest` e no `Info.plist` (conferir o que as fotos já pedem).
**Aceite:** no emulador Android, gravar um vídeo curto no meio do treino,
enviar e continuar registrando séries durante o upload; arquivo acima do limite
é recusado com mensagem; com a rede cortada a ação informa e o treino segue;
teste de widget da folha (aviso visível, limite, sem consentimento).

## - [x] P12.3 App — professor avalia a mídia (Flutter, coach)

**Objetivo:** ver, dar ciência e responder.
**Passos:**
1. Aba Check-ins da ficha: seção "Para avaliar" no topo com as mídias sem
   ciência (independe de o aluno ter feito check-in); no card e no detalhe do
   treino (P11.2), as mídias daquela sessão.
2. Visualizador: vídeo (`video_player`) ou imagem, observação do aluno,
   exercício, e as ações **Marcar como visto** e **Responder** (texto → vai
   para o chat do aluno, D7). Antes de confirmar qualquer uma, o aviso: "a
   mídia será apagada em 7 dias". Depois: selo "Apagada em DD/MM".
3. Mídia expirada: card esmaecido "Mídia expirada" (sem player).
4. Dashboard: o card de check-ins não revisados soma/mostra `unacked_media`.
   Toque na notificação de mídia nova abre a ficha na aba Check-ins.
**Aceite:** professor recebe a mídia, assiste, responde; o aluno vê a resposta
no chat e o estado "visto" no player/lista; após o ack o card mostra a data de
exclusão; teste de widget do visualizador (aviso antes do ack) e da seção
"Para avaliar".

## - [ ] P12.4 E2E do 2.5 e release 2.5.0 (humano + agente)

**Objetivo:** fechar o pacote.
**Passos:**
1. Roteiro `e2e-25.md`, uma linha por pedido do cliente (tabela "Origem →
   tarefa" do README), coach no Chrome e aluno no emulador Android com a rede
   cortada no treino: variação e cluster prescritos → treino com chips e (i)
   offline → replicar carga → cronômetro → modal de conclusão com voltar →
   mídia enviada → check-in → professor vê métricas, detalhe e mídia, responde
   → job de expiração (relógio adiantado em teste, não manual).
2. Regressão: [e2e-2.md](../mvp2/e2e-2.md) nos passos de builder, player e
   check-in; smoke do 1.0 ([e2e-p1.md](../mvp1/e2e-p1.md)).
3. Varredura: `go vet`/`go test` nos serviços tocados (workout, comms,
   identity), `flutter analyze && flutter test`.
4. Versão `2.5.0+3` (pubspec, `APP_RELEASE`, README), APK release e build web
   (ADR-015, sem loja). Atualizar CLAUDE.md (Estado atual) e o STATUS.
**Aceite:** roteiro verde no Android (emulador) e no Chrome; achados
classificados (corrige agora / vai para o 3.0) nas Notas; artefatos gerados.

---

## Notas de execução

**P12.3 (2026-11-16)**

- Código em `app/lib/features/session_media/`: `presentation/coach_media_controller.dart` (`coachMediaProvider(studentId)`), `coach_media_viewer.dart` (visualizador) e `coach_media_widgets.dart` ("Para avaliar", mídias da sessão, linha da mídia). Modelo `SessionMedia` ganhou `studentId`/`sessionClientId`/`withAck`; `SessionMediaRepository` ganhou `listForCoach` e `ack`.
- Chamadas: ao abrir a aba Check-ins, o controller faz `GET /v1/session-media?student_id=&pending=true&limit=100` (seção "Para avaliar", com cursor próprio e botão "Carregar mais") e `GET /v1/session-media?student_id=&limit=100` seguindo `next_cursor` até 3 páginas (cards e detalhe agrupam por `session_client_id`, pois o servidor não filtra por sessão). Ack: `POST /v1/session-media/{id}/ack {feedback?}`; o controller tira o item de "Para avaliar" e atualiza card/detalhe sem recarregar. Puxar para atualizar recarrega as duas listas. O rótulo da aba soma não revisados + mídias sem ciência.
- Visualizador: vídeo (`video_player` com play/pausa e barra) ou imagem, exercício, observação; o aviso "será apagada em 7 dias" fica visível antes de **Marcar como visto**/**Responder**; depois do ack vira "Apagada em DD/MM". Responder abre o campo e manda o texto como `feedback` do ack (vira mensagem no chat do aluno, D7); Responder segue disponível depois do ack (o prazo não renova). Erro no ack mostra a mensagem e mantém o aviso.
- Expirada: card esmaecido "Mídia expirada" sem player. Dashboard: `GET /v1/checkins/stats` agora vira `CheckinStats` (`unreviewed` + `unacked_media`); o card mostra "N mídias para avaliar" abaixo do número.
- Push: `session_media.new` mapeia para o mesmo deep link de `checkin.pain_strong` (`/students/{student_id}?tab=checkins`); o botão de back da ficha segue o roteamento existente.
- Verificação: `flutter analyze` limpo, `flutter test` 298 verdes (novo `test/features/session_media/coach_media_test.dart`: aviso antes do ack, ack sem texto, resposta com feedback, erro, seção "Para avaliar" com ack, vista/expirada na sessão, deep link do push), `flutter build web` compila.
- **Verificar manualmente (não feito aqui):** (1) coach no Chrome recebe a mídia do aluno do emulador, assiste ao vídeo (formato `video/mp4` do Android no player web) e vê a miniatura/URL assinada; (2) Marcar como visto: selo com a data = hoje + 7 dias e a mídia sai de "Para avaliar"; (3) Responder: o aluno vê a mensagem no chat e "Visto pelo professor" na lista do player; (4) push `session_media.new` em aparelho físico abre a aba Check-ins (depende do `google-services.json`); (5) mídia expirada pelo job aparece esmaecida.
- Dívidas: (1) o card e o detalhe só conhecem as mídias das 300 mais recentes do aluno (sem filtro por sessão no servidor); (2) imagem usa `Image.network` simples, vídeo não tem miniatura na lista; (3) o aluno revogar `progress_photos` não esconde a mídia do coach (dívida 1 da P12.1).

**P12.2 (2026-11-16)**

- Código em `app/lib/features/session_media/`: `domain/session_media.dart` (modelo + limites 20 MB / 3 por sessão / 280 da nota), `data/session_media_repository.dart` (presign → PUT com progresso e `CancelToken` → registro; `Dio` limpo no PUT, igual ao chat e às fotos de progresso), `data/media_preparer.dart` (seletor + compressão atrás de `MediaPreparer`, trocável no teste), `presentation/session_media_controller.dart` (envio fora da tela), `send_media_sheet.dart` e `session_media_section.dart`.
- Onde fica a ação: ícone de câmera de vídeo no cabeçalho do cartão de cada exercício (straight e blocos bi-set/circuito/dropset/rest-pause/cluster) e item "Enviar vídeo ao professor" no menu ⋮ da AppBar do player (sem exercício). "Enviados neste treino" é o último item da lista do player.
- Não bloqueia: a folha só escolhe/comprime/valida e entrega ao `SessionMediaController` (`NotifierProvider.family` por `session.clientId`, vivo enquanto o app roda), fecha na hora e o upload segue assíncrono — nenhum caminho do `logSet`, do cronômetro, do `ExerciseFieldsRegistry` ou do modal de conclusão passa por ele. Um envio por vez; progresso, cancelar e "tentar de novo" na linha da lista; falha mantém os bytes na memória enquanto o app estiver aberto (sem fila persistente, ADR-020).
- Compressão e limite: vídeo `pickVideo(maxDuration: 60 s)` + `VideoCompress` (MediumQuality, com áudio) → MP4; se o plugin devolver `null` segue o original e o tamanho decide. Foto: mesma compressão JPEG (1280 px, q82) das fotos de progresso. Web: sem compressão. Acima de 20 MB (depois de comprimir): mensagem com o tamanho (`sessionMediaTooLarge`), nada vai ao servidor. O servidor continua validando (`file_too_large`, `session_media_limit`...).
- Consentimento e offline: a folha lê `consentStatusProvider` (`GET /v1/me/consents`). Sem `progress_photos` mostra o aviso e o botão "Abrir privacidade" (leva à Conta) e não oferece câmera; sem rede esse `GET` falha e a folha explica que precisa de conexão (o treino segue); com 3 mídias mostra o limite. O aviso de retenção (20 MB, 7 dias após ver/responder, 30 dias) aparece sempre, antes de escolher o arquivo.
- `describeApiError` ganhou `session_media_limit`, `invalid_media_key`, `media_not_uploaded` e `file_too_large` com `max_bytes` (o texto antigo de 50 MB só vale sem o parâmetro).
- Permissões: `CAMERA` e `RECORD_AUDIO` (+ `uses-feature` não obrigatório) no `AndroidManifest`; chaves do `Info.plist` no `app/README.md` (iOS é gerado). `video_compress ^3.1.4` no `pubspec` (D4).
- Verificação: `flutter analyze` limpo, `flutter test` 291+ verdes (novo `test/features/session_media/`: folha com aviso, limite de tamanho, limite de 3, sem consentimento, offline, envio que fecha a folha e segue em segundo plano; lista com enviado/visto/expirado e remover; controller com falha + retry e um envio por vez), `flutter build apk --debug` e `flutter build web` compilam com o `video_compress`.
- **Verificar manualmente no emulador Android (não feito aqui):** (1) gravar um vídeo curto pela câmera no meio do treino e ver a compressão (MP4 menor); (2) enviar e continuar registrando séries durante o upload (cronômetro e descanso seguem); (3) arquivo > 20 MB da galeria é recusado com o tamanho; (4) rede cortada: a folha informa a necessidade de conexão e o treino segue; cortar a rede no meio do upload mostra "Tentar de novo" e retomar funciona; (5) conta sem `progress_photos` cai na tela Conta; (6) iOS: conferir as chaves do `Info.plist`.
- Dívidas: (1) o aluno não vê a miniatura de vídeo (só ícone; sem geração de thumbnail); (2) a lista só recarrega do servidor ao abrir o player (estado "visto" aparece ao reabrir, não em tempo real); (3) o botão de mídia por exercício adiciona um ícone ao cabeçalho do cartão — se o cliente achar poluído, mover para o menu.

**P12.1 (2026-11-16)**

- Rotas (comms): aluno `POST /v1/me/session-media/presign`, `POST /v1/me/session-media`,
  `GET /v1/me/session-media?session_client_id=`, `DELETE /v1/me/session-media/{id}`;
  professor/owner `GET /v1/session-media?student_id=&pending=` e
  `POST /v1/session-media/{id}/ack`; `GET /v1/checkins/stats` ganhou `unacked_media`.
  Migration comms `0008_session_media` (RLS, 3 índices; `media_key` nullable: some na expiração).
- Erros 422 do fluxo: `file_too_large` (presign > 20 MB, ou objeto > 20 MB no HEAD do
  registro), `unsupported_media_type`, `invalid_media_key`, `media_not_uploaded` (HEAD 404),
  `session_media_limit` (4ª mídia; o objeto recusado é apagado do storage). Tamanho e tipo
  gravados vêm do HEAD, não do cliente. 403 `consent_required` sem `progress_photos` nas
  claims (só no presign e no registro: listar e retirar nunca são barrados).
- O limite de 3 por sessão conta linhas (inclusive expiradas) sob `pg_advisory_xact_lock`
  da sessão. Registrar a mesma chave de novo devolve a linha existente (idempotente).
- Ack: `delete_after = LEAST(delete_after, acked_at + 7d)` num UPDATE condicionado a
  `acked_at IS NULL`; o relógio do instante da ciência é injetável no handler. Feedback
  vira mensagem de texto do próprio ator (coach ou owner) no chat direto com o aluno, via
  `ConversationHandler.PostText` (mesmo caminho do chat: `message.new` no WS dos dois e
  push se o aluno estiver offline). O corpo é `[exercício · AAAA-MM-DD] texto` (cabeçalho
  neutro quanto ao idioma). Ack + feedback repetidos reenviam a mensagem (sem dedupe).
- Job de expiração (`internal/job/media_expiry.go`): tick de 5 min, mesmo
  `pg_try_advisory_lock` (chave `pendingLockKey`) do job de treino pendente — uma instância
  por vez, quem não pega o lock volta no tick seguinte. O RLS exige um tenant por consulta,
  então varre os tenants listados pelo identity (`tenantclient`, como o job de pendentes).
  Apaga o objeto e só então marca `deleted_at` (+ `media_key = NULL`); falha no S3 não marca.
  Relógio injetável (`WithClock`).
- Storage: `media.Presigner` ganhou `PresignSessionMediaPut`, `Head`, `DeleteObject`,
  `DeleteStudentObjects` (só a pasta `.../session-media/` do aluno: as fotos de evolução do
  assessment dividem a árvore `tenants/{t}/students/{s}/` e não podem ser tocadas) e
  `SignedReadURL` (sempre assinada, ignora `S3_PUBLIC_BASE_URL`: mídia de execução nunca é
  pública). Exclusão de conta: o handler apaga os objetos e depois `ErasureRepo` apaga as
  linhas e anonimiza `acked_by`.
- Termos: `TERMS_VERSION` `2026-11-v2` → `2026-11-v3` (identity `config.go`/`.env.example`,
  `AppConfig.termsVersion`, `app/README.md` e os 6 textos de `assets/legal/`, que passam a
  citar a mídia de execução, a retenção de 7/30 dias e a retirada pelo aluno). Todo usuário
  aceita de novo no primeiro login; `.env` locais com `TERMS_VERSION` explícito precisam
  acompanhar. Revisão jurídica segue na L6 do pré-loja.
- Dívidas: (1) o coach continua vendo a mídia depois que o aluno revoga `progress_photos`
  até ela expirar (o assessment bloqueia a leitura do coach nesse caso; aqui exigiria
  consulta M2M de consentimento no `GET /v1/session-media`); (2) o cabeçalho da mensagem de
  feedback não é traduzido; (3) o push de mídia nova só vai ao coach atual do aluno
  (`CoachOf`), nunca ao owner; (4) sem teste automatizado de PUT real de 20 MB — o teto é
  garantido pela assinatura (conferido contra o MinIO no HEAD do round-trip de 14 bytes).
