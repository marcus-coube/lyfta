# P3 — Comunicação (chat, avaliação de treino, push)

Meta da fase: aluno e professor conversam (texto+imagem) em tempo real; aluno
avalia o treino ao concluir (feedback/dificuldade/dor); push de nova mensagem e de
treino pendente. Chat com mídia rica (áudio/vídeo/PDF) fica no 3.0 (ADR-012).

Refs normativas: ADR-012 (escopo texto+imagem), ADR-013 (comms + M2M), ADR-011.

---

## - [ ] P3.1 Serviço comms — esqueleto + schema

**Objetivo:** serviço de comunicação de pé.
**Passos:** bootstrap padrão + Redis (pub/sub para fan-out de WS entre instâncias —
mesmo com 1 instância, já nasce certo). Migrations:
- `conversations (id, tenant_id, student_id, coach_id, created_at,
  last_message_at)` — 1 conversa por par aluno-coach (unique).
- `messages (id, tenant_id, conversation_id, sender_id, type: text|image, body,
  media_key, created_at, read_at)`.
- `workout_checkins (id, tenant_id, student_id, session_client_id, rating 1..5,
  difficulty 1..5, pain: none|mild|strong, pain_notes, comment, created_at,
  reviewed_by, reviewed_at)`.
- `device_tokens (id, tenant_id, user_id, platform: android|ios|web, token,
  updated_at)`.
- `notification_log (id, tenant_id, user_id, kind, payload, sent_at)`.
**Aceite:** migrations limpas; RLS testada.

## - [ ] P3.2 comms — chat REST + WebSocket

**Objetivo:** troca de mensagens em tempo real com histórico.
**Endpoints:**
- `GET /v1/conversations` (coach vê uma por aluno; aluno vê a sua) com preview e
  contador de não lidas; `GET /v1/conversations/{id}/messages` (cursor desc);
  `POST /v1/conversations/{id}/messages` (text|image; imagem via presign padrão,
  key `tenants/{t}/chat/{conv}/{uuid}`); `POST .../read` (marca lidas).
- `GET /ws?token=` (JWT no query — WS não manda header): eventos
  `message.new`, `message.read`; publish no Redis, fan-out por conexão inscrita na
  conversa. Reconexão do cliente recupera o gap via REST (cursor) — WS é só
  entrega quente, a verdade é o banco.
**Aceite:** teste de integração: 2 conexões WS trocam mensagem; queda de WS não
perde mensagem (REST recupera); não lidas zeram no read.

## - [ ] P3.3 comms — check-in de treino (avaliação)

**Objetivo:** feedback estruturado do aluno ao concluir o treino.
**Endpoints:** `POST /v1/checkins` (aluno; 1 por `session_client_id` — idempotente);
`GET /v1/checkins?student_id=` (coach, cursor) + `POST /v1/checkins/{id}/review`
(marca visto); dor `strong` dispara push imediato pro coach (P3.4).
**Aceite:** duplicata de check-in não cria segundo registro; listagem do coach
ordena não revisados primeiro.

## - [ ] P3.4 comms — push FCM + job de treino pendente

**Objetivo:** as duas notificações do MVP (ADR-012): nova mensagem e treino pendente.
**Passos:**
1. Setup Firebase (projeto `lyfta-dev`), Admin SDK no comms (`FCM_CREDENTIALS_JSON`
   env). `POST /v1/devices` registra token (upsert por user+platform).
2. Push `message.new` para o destinatário se ele não estiver conectado no WS
   (checagem via registry Redis das conexões ativas). Push de check-in com dor
   forte para o coach. Render no locale do destinatário (claim `locale`) — chaves
   de tradução no serviço (ADR-011: server renderiza push).
3. Job diário (goroutine ticker + advisory lock) "treino pendente": consulta
   `workout` via `GET /internal/v1/pending-students` (endpoint interno no workout,
   auth `X-Internal-Token`: alunos com plano ativo e sem sessão hoje até as 18h
   locais do tenant) → push "Seu treino de hoje te espera 💪". Registrar em
   `notification_log` (dedupe 1/dia por aluno).
**Aceite:** push chega no Android físico/emulador com Play Services; job não
duplica no mesmo dia; log de notificações consultável.

## - [ ] P3.5 Flutter — chat, avaliação e notificações

**Objetivo:** fechar a comunicação no app, nos dois papéis.
**Passos:**
1. `features/chat/`: lista de conversas (coach) / conversa direta (aluno), bolhas
   texto+imagem, envio com estado otimista, indicador não lidas no ícone da tab,
   reconexão WS transparente (recupera via REST). Imagem: picker + compressão +
   presign (reusar infra do P2.4).
2. Avaliação pós-treino: ao finalizar sessão (P1.7), bottom sheet: rating (1–5),
   dificuldade (1–5), dor (nenhuma/leve/forte + onde), comentário opcional; envia
   quando online (fila local — reusa `pending_events`? **não**: check-in é online,
   ADR-003 restringe offline à execução; se offline, salva rascunho local simples e
   envia ao reconectar com aviso).
3. Coach: aba de check-ins na ficha do aluno (badge de não revisados) + review.
4. `firebase_messaging`: permissão, registro do token, tap na notificação abre a
   conversa/treino (deep link via go_router). Web: **apenas badge in-app** no MVP
   (web push fica pro 3.0 — anotar em Notas).
**Aceite:** fluxo real entre 2 devices (coach web + aluno Android): mensagem chega
via WS, push chega com app fechado, check-in aparece pro coach; teste de widget da
bolha de mensagem e do form de check-in.

---

## Notas de execução

(o agente anota aqui descobertas, dívidas e desvios aprovados)
