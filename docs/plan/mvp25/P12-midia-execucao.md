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

## - [ ] P12.1 Mídia de execução (comms)

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

## - [ ] P12.2 App — anexar mídia no treino (Flutter, aluno)

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

## - [ ] P12.3 App — professor avalia a mídia (Flutter, coach)

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

(o agente anota aqui descobertas, dívidas e desvios aprovados)
