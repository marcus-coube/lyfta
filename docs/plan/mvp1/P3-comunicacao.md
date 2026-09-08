# P3 — Comunicação (chat, avaliação de treino, push)

Meta da fase: aluno e professor conversam (texto+imagem) em tempo real; aluno
avalia o treino ao concluir (feedback/dificuldade/dor); push de nova mensagem e de
treino pendente. Chat com mídia rica (áudio/vídeo/PDF) fica no 3.0 (ADR-012).

Refs normativas: ADR-012 (escopo texto+imagem), ADR-013 (comms + M2M), ADR-011.

---

## - [x] P3.1 Serviço comms — esqueleto + schema

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

## - [x] P3.2 comms — chat REST + WebSocket

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

## - [x] P3.3 comms — check-in de treino (avaliação)

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

**P3.1:** quinto microserviço, `comms` (8084, banco `lyfta_comms`) — bootstrap
idêntico ao assessment (chi+pgxpool+slog, JWT EdDSA validado com a chave pública
do identity, `/healthz` + `/v1/whoami`, `internal/security`/`internal/repo`
duplicados, nenhum import entre serviços, ADR-013 §2). 6 migrations com as 5
tabelas do plano — `conversations` (unique por tenant+student+coach),
`messages` (append-only, `CHECK` casando `type` com `body`/`media_key`),
`workout_checkins` (unique por tenant+`session_client_id`, idempotência igual
à do workout), `device_tokens` (unique por tenant+user+platform, upsert-ready)
e `notification_log` — todas com RLS forçada e policy `tenant_isolation`,
índice começando por `tenant_id`. Dependência nova: `github.com/redis/go-redis/v9`
(cliente oficial recomendado pelo Redis) — Redis já é infra pinada
(`backend/README.md`/`docker-compose.yml`), faltava só o driver Go, mesmo
raciocínio do `aws-sdk-go-v2` na P1.2. `internal/pubsub/redis.go` cria o
client e confirma com `PING` na subida (falha cedo, como o pool do Postgres);
o fan-out de WS de fato (publish/subscribe por conversa) é escopo da P3.2 —
aqui só o mecanismo básico é testado (round-trip publish→subscribe).

Índice de dedupe do `notification_log` mudou de funcional (`sent_at::date`)
para simples (`tenant_id, user_id, kind, sent_at DESC`): o cast
`timestamptz -> date` não é `IMMUTABLE` (depende do timezone da sessão) e o
Postgres recusa a migration. A consulta de dedupe do job diário (P3.4) filtra
por uma faixa `[início do dia, início do dia seguinte)` sobre esse índice —
descoberto rodando a migration local, não é uma dívida, é a forma certa.

CI ganhou o step condicional de Redis para o job `comms` (mesmo padrão do
MinIO para workout/assessment) e a env `REDIS_URL` no `go test`. 8 testes
verdes (isolamento cross-tenant nas 5 tabelas, RLS bloqueia escrita sem
`app.tenant_id`, unicidade de `conversations` e de `workout_checkins`,
ping+round-trip do Redis, healthz público, whoami rejeita/aceita token).
`gofmt`/`go vet` limpos, reversibilidade `down -all`→`up` verificada, e smoke
com `identity`+`comms` reais no ar: signup gerando token real autenticando no
`/v1/whoami`.

**P3.2:** chat REST + WebSocket. Duas dependências novas, ambas pré-aprovadas
na sessão: `github.com/gorilla/websocket` (lib mais consolidada do
ecossistema Go, casa bem com chi/`net/http` via `Upgrader` — linha nova em
`backend/README.md` § Stack pinada) e `aws-sdk-go-v2` (`service/s3` +
`credentials`) no comms, quitando a dívida de mídia anotada na P3.1 (mesmo
presigner do workout/assessment, adaptado: `internal/media`, key
`tenants/{t}/chat/{conversation_id}/{uuid}.ext`, `ValidKeyForConversation`
como par de segurança). `S3_*` virou obrigatória em `internal/config` e
entrou no `.env.example`/`.env` do comms.

Endpoints (`internal/http/conversations.go`, `media.go`, `ws.go`):
`GET /v1/conversations` (prévia + não lidas via `LEFT JOIN LATERAL` +
subquery, sem porta `/me`×`/students/{id}` — aluno e coach acessam a mesma
conversa, autorização é "sou participante", checada dentro do handler),
`GET/POST /v1/conversations/{id}/messages` (cursor keyset por
`created_at,id` com precisão de instante — `internal/http/cursor.go` é
irmão do cursor do assessment, mas RFC3339Nano em vez de `DateOnly`: mensagem
acontece várias por segundo), `POST .../read` (zera não lidas do leitor,
idempotente), `POST .../media/presign`. O plano só descrevia
`GET /v1/conversations` — como abrir uma conversa nova não estava no plano,
acrescentei `POST /v1/conversations {student_id}` (só coach/owner, "qualquer
professor do tenant" — mesmo critério do P1.4/P2.1/P2.3) fazendo
get-or-create sobre a unique da migration 0001: é a peça que faltava para o
chat ser utilizável e não conflita com nenhum ADR, então segui em vez de
parar (registrado aqui em vez de silenciar).

WebSocket: `GET /ws?token=` (token na query — o handshake do browser não
manda header customizado) autentica com o mesmo `security.JWTVerifier`,
depois `internal/ws.Hub` registra a conexão por `user_id` (mais de uma por
usuário — múltiplos devices). Fan-out entre instâncias via Redis
(`internal/pubsub`): o handler REST publica o evento serializado no canal
`comms:user:{id}` de cada participante (não por conversa — como quem publica
já filtra pelos dois participantes da conversa, publicar por usuário é mais
simples e a P3.4 reusa o mesmo canal para decidir se manda push);
`pubsub.Relay` é uma goroutine única por instância que assina
`comms:user:*` e entrega ao `Hub` local — sem isso a instância que recebeu o
POST e a instância com a conexão WS do destinatário poderiam ser processos
diferentes. Confirmado que `StructuredLogging` não vaza o token: loga
`r.URL.Path`, que no `net/http` já exclui a query string — nenhuma redação
extra foi necessária (só o comentário em `router.go` registrando a
verificação).

Teste de integração (`internal/http/chat_integration_test.go`,
`TestChatEndToEnd`) sobe o roteador real atrás de `httptest.NewServer`
(WebSocket precisa de hijack de verdade — `ResponseRecorder` não serve) com
Postgres/Redis reais (mesmo padrão skip-fora-do-CI/fail-no-CI dos demais
testes de integração do serviço) e cobre o Aceite literal: duas conexões WS
(aluno e coach) recebem `message.new` quando o aluno manda texto; o WS do
coach cai (`Close()`), uma mensagem chega nesse meio tempo, e o histórico
REST do coach recupera as duas mensagens sem perda; `POST .../read` zera
`unread_count` de 1 para 0. `TestChatAuthorizationAndValidation` cobre as
bordas (tipo inválido, imagem sem `media_key`, `media_key` de outra
conversa, usuário de fora recebendo 403, conversa inexistente 404 em vez de
vazar 403). `internal/repo/conversations_test.go` cobre get-or-create
idempotente, paginação por cursor e que `MarkRead` só afeta mensagens do
outro participante. `internal/ws.Hub` ficou só em memória por instância
(sem presença em Redis) — a P3.4 pede explicitamente esse registro
Redis-backed para decidir push, então fica para lá em vez de antecipar aqui.

CI: passo do MinIO passou a subir também para `matrix.service == 'comms'`
(mesma condição do workout/assessment). `gofmt`/`go vet` limpos, todos os
testes verdes (incluindo `-race`), e smoke com `identity`+`comms` reais no
ar: signup do coach pelo `identity`; para o aluno, o e-mail de convite não
tinha como ser lido nesta sessão, então o token de acesso do aluno foi
assinado à mão com a chave privada do `identity` (mesmas claims que o
`/v1/auth/login` emitiria — não é um caminho novo, só um atalho para não
depender de inbox no smoke manual), e a partir daí: conversa criada pelo
coach, mensagem de texto trocada, não lida zerando no read, presign de
imagem com `PUT` real no MinIO e leitura do `media_url` assinado de volta.

**P3.3:** check-in de treino. Nenhuma migration nova — a `workout_checkins`
da P3.1 já tinha todas as colunas do plano. `POST /v1/checkins` (sem
restrição de papel, mesmo critério do `/v1/sync/workout-logs` do workout):
`student_id` vem só da claim (`claims.Subject`), nunca do corpo — se o
corpo mandar `student_id` ele é ignorado, não decodificado. Idempotência
pela unique `(tenant_id, session_client_id)` com o mesmo truque do
`ConversationRepo.GetOrCreate` (`ON CONFLICT ... DO UPDATE SET tenant_id =
tenant_id` só para forçar o `RETURNING` da linha existente): reenvio da
mesma sessão com dados diferentes devolve os dados **originais**, não
sobrescreve.

`GET /v1/checkins?student_id=` (coach/owner) trata `student_id` como
filtro **opcional**, não obrigatório — decisão registrada aqui em vez de
travar a tarefa: a P3.5 usa esse endpoint tanto na aba de check-ins da
ficha do aluno (com `student_id`) quanto, potencialmente, numa fila geral
do coach (sem filtro); e o índice `idx_workout_checkins_pending` da P3.1
foi desenhado sem coluna de aluno, o que só faz sentido para a consulta
sem filtro. Ordenação (Aceite: "não revisados primeiro, depois
cronológico") é `reviewed_at NULLS FIRST, created_at DESC, id DESC` nos
dois casos. `EXPLAIN` confirmado neste ambiente: sem `student_id`, o plano
usa `idx_workout_checkins_pending` (com `enable_bitmapscan`/`seqscan`
desligados vira `Index Scan` + `Incremental Sort`, aproveitando a
pré-ordenação do índice; com o planner padrão, no volume pequeno do dev,
vira `Bitmap Heap Scan` sobre o mesmo índice + `Sort` explícito — o índice
é usado nos dois casos, só não elimina o `Sort` a essa escala); com
`student_id`, o Postgres troca para `idx_workout_checkins_student` e
ordena em memória — aceitável porque o volume por aluno é pequeno.

Cursor keyset ficou em 3 campos (`reviewed_at` + `created_at` + `id`) em
vez dos 2 do cursor de mensagens, porque a ordenação mistura uma coluna
nullable em ASC (NULLS FIRST) com `created_at` em DESC — não dá pra usar
comparação de tupla simples. Armadilha encontrada e corrigida ainda nesta
tarefa: a primeira versão usava um "zero-time" do Go como sentinela de "não
revisado" e comparava contra o `-infinity` do SQL — os dois não são o mesmo
valor (`0001-01-01` é maior que `-infinity`), então a segunda página vinha
sempre vazia. A correção usa `*time.Time` nulo de verdade dos dois lados
(`COALESCE(reviewed_at, '-infinity') = COALESCE($1, '-infinity')`), com um
parâmetro à parte (`$2 IS NULL`) só para dizer "sem cursor" — coberto por
`TestCheckinListPagination`.

Dor `strong` publica um evento (`checkin.pain_strong`) no canal Redis
`comms:user:{coach}` que o P3.2 já criou, mesmo formato dos eventos de
chat — sem tocar no `internal/ws.Hub` nem antecipar FCM (isso é P3.4).
"Qual é o coach" resolve consultando as próprias `conversations` do comms
(o par aluno-coach já vive aqui desde a P3.1): publica para todo coach com
quem o aluno já tem conversa aberta. Se ainda não existir nenhuma
conversa, nada é publicado — o alcance completo ("qualquer professor do
tenant", independente de chat já aberto) depende do vínculo coach↔aluno do
identity, dívida já anotada desde o P1.4, e do FCM da P3.4.

`gofmt`/`go vet` limpos, 27 testes verdes (11 novos: 6 de repositório
cobrindo idempotência/ordenação/paginação/filtro por aluno/revisão
idempotente/not-found, 6 de integração HTTP sobre `httptest.NewServer`
com Postgres+Redis reais cobrindo o Aceite literal, autorização por papel,
validação de campos e o gancho de push), inclusive com `-race`. Smoke
manual com `identity`+`comms` reais: signup real do coach, token de aluno
assinado à mão com a chave privada do identity (mesmo atalho do smoke da
P3.2, sem depender de convite por e-mail) — aluno cria check-in, reenvio
idempotente confirmado, coach lista e revisa, aluno tentando listar recebe
403.
