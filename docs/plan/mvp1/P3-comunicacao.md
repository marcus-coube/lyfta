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

## - [x] P3.4 comms — push FCM + job de treino pendente

**Objetivo:** as duas notificações do MVP (ADR-012): nova mensagem e treino pendente.
**Passos:**
1. Setup Firebase (projeto `lyfta-a3bd3`), Admin SDK no comms (`FCM_CREDENTIALS_JSON`
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

## - [x] P3.5 Flutter — chat, avaliação e notificações

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

**P3.4:** push FCM + job de treino pendente. O passo 1 (setup do Firebase,
projeto `lyfta-a3bd3`) já estava feito e commitado antes desta tarefa
(commit `cbaf599`); aqui entrou só código.

Cliente FCM: `golang.org/x/oauth2/google` + chamada HTTP direta à FCM v1
(`internal/fcm`), não o Admin SDK oficial (`firebase.google.com/go/v4`) —
dependência nova registrada em `backend/README.md` § Stack pinada. O SDK
oficial cobre a mesma necessidade (mandar 1 mensagem por token), mas
arrasta uma árvore pensada pro produto Firebase inteiro (Firestore,
Storage, Auth...); `go mod tidy` confirmou que a escolha minimalista trouxe
só `golang.org/x/oauth2` (direto) e `cloud.google.com/go/compute/metadata`
(indireto, pequeno) — nada de `cloud.google.com/go` inteiro. `NewClient`
decodifica a service account (`FCM_CREDENTIALS_JSON`, caminho de arquivo ou
JSON inline, já documentada desde o setup do Firebase) e monta um
`http.Client` que renova o token OAuth2 sozinho; `Send` fala HTTP v1 puro e
mapeia token morto (`UNREGISTERED`/`NOT_FOUND`) para `ErrUnregistered`, que
o `internal/push.Notifier` usa pra apagar o device_token (senão o job
tentaria mandar pro mesmo token morto todo dia). Sem
`FCM_CREDENTIALS_JSON` configurada, o serviço sobe do mesmo jeito com push
desligado (`Notifier` com `pusher` nil, só loga) — decisão deliberada pra
não travar CI/dev sem Firebase por causa de uma feature que não bloqueia
chat nem check-in; com credencial inválida, falha cedo (mesmo critério do
resto da config).

**Locale do destinatário:** a claim `locale` do JWT (ADR-011 §3) só ajuda
quando o request em mãos é do PRÓPRIO destinatário — mas em nenhum dos dois
casos de push isso é verdade. Nos eventos em tempo real (`message.new`,
`checkin.pain_strong`) as claims disponíveis no request são sempre de quem
DISPARA o evento (remetente/aluno), nunca de quem vai receber; e o job
diário roda numa goroutine, sem request nenhum. Por isso `device_tokens`
ganhou a coluna `locale` (migration `0007_device_tokens_locale`, `NOT NULL
DEFAULT 'pt-BR'`), gravada a cada `POST /v1/devices` — é a única fonte do
idioma do destinatário disponível fora de uma requisição HTTP dele, e serve
os dois casos (tempo real e job) com um único caminho em vez de dois
divergentes. `internal/push/messages.go` renderiza pt-BR/pt-PT/en a partir
dela, com fallback pt-BR se o valor gravado não for um dos três (nunca
deveria acontecer — a coluna não tem `CHECK`, só o handler valida antes de
gravar).

**Timezone do job:** o plano fala em "até as 18h locais do tenant", mas não
existe coluna de timezone em nenhuma tabela de tenant (nem identity nem
comms) e criá-la seria migration no identity — fora do escopo desta tarefa
(P3.4 é só comms + 1 endpoint interno no workout). Resolvido com um default
único no comms: env `NOTIFICATION_TIMEZONE` (`America/Sao_Paulo`), aplicado
a **todos** os tenants por ora. **Dívida técnica registrada**: quando
houver timezone por tenant (provável extensão do identity), o job precisa
varrer por tenant com o fuso de cada um, em vez de uma janela `[since,
until)` global — não é mudança grande (o `workoutclient.PendingStudents` já
recebe `since`/`until` como parâmetros, então vira "chamar N vezes, um por
fuso distinto entre os tenants", não redesenhar o mecanismo).

**Presença entre instâncias:** a Nota da P3.2 já previa que o
`internal/ws.Hub` só sabe das conexões da própria instância, e que a P3.4
precisaria de um registro compartilhado pra decidir push de `message.new`.
Criado `internal/pubsub/presence.go`: um Set Redis por usuário
(`comms:presence:{user_id}`), `SADD`+`EXPIRE` (90s, renovado a cada ping de
30s do WS) no registro da conexão, `SREM` no fechamento — o TTL cobre o
processo caindo sem fechar a conexão direito (`kill -9`), sem isso a marca
ficaria órfã para sempre. `ConversationHandler.SendMessage` consulta
`pubsub.IsOnline` do **outro** participante (nunca de quem mandou) antes de
notificar: online, só WS (evita duplicar como push); offline, `Notifier`
entra em ação.

**Push de dor forte** (`CheckinHandler`) é **sempre** enviado ao coach,
esteja ele online ou não — ao contrário de `message.new`, o texto do plano
não condiciona esse push à presença ("dor é importante o bastante pra tocar
mesmo com o app aberto"), então a assinatura ficou deliberadamente
assimétrica em vez de reusar a mesma checagem de presença.

**Job diário** (`internal/job.PendingWorkoutJob`): ticker de 5 minutos
checando se já passou da hora de disparo (18h, `time.Location` de
`NOTIFICATION_TIMEZONE`) e ainda não varreu hoje (`lastSweptDay` em
memória — evita bater no workout a cada tick pelo resto do dia depois do
primeiro sweep bem-sucedido). Duas camadas de proteção contra duplicata,
cada uma cobrindo um cenário diferente: `pg_try_advisory_lock` (não
bloqueante, `hashtext('lyfta_comms_pending_workout_job')::bigint`) evita
que duas instâncias do comms varram ao mesmo tempo; dedupe por
`notification_log` (`NotificationLogRepo.ExistsInRange`, filtro por faixa
`[since, until)` sobre o índice simples da P3.1 — o mesmo motivo de não dar
pra usar índice funcional por `date` já registrado lá) evita reenviar pro
mesmo aluno se o processo reiniciar e varrer de novo no mesmo dia. Se
**todos** os envios de um aluno falharem (sem device token, ou FCM
recusando todos), nenhum `notification_log` é gravado para ele — ele só é
tentado de novo se o processo reiniciar antes da meia-noite (`lastSweptDay`
reseta), porque o ticker não força um segundo sweep no mesmo dia uma vez
que o primeiro já rodou; aceito como limitação de MVP (o volume de
"pendentes" tende a ser pequeno e o cenário é raro — sem device token
nenhum registrado é o caso mais comum, e aí não há o que reenviar mesmo).

**Endpoint interno no workout** (`GET /internal/v1/pending-students`):
mesma solução de M2M cross-tenant que o identity já usa desde a P0.3
(`find_tenants_by_email`, migration `0008_email_lookup`) — função SQL
`SECURITY DEFINER` de superfície mínima (`find_pending_students`, migration
`0016_pending_students`), porque a consulta precisa atravessar TODOS os
tenants de propósito (é um job, não uma requisição de usuário com
`app.tenant_id` setado) e a RLS forçada bloquearia isso do jeito normal.
"Plano ativo" usa o mesmo critério que o resto do serviço já assume
(`GetState`/`MyPlan`): existir uma linha em `student_plan_state`, sem
reconferir `workout_plans.status` — ela só existe depois de um `Publish` e
é sempre reescrita pra apontar pro plano atualmente publicado. "Sem sessão
no intervalo" filtra por `workout_sessions.received_at` (carimbo do
servidor, ADR-003 §2), não `started_at` (relógio do device, não confiável)
— mesma fonte de verdade que a P1.5 já usa. O intervalo `[since, until)` é
decidido inteiramente pelo comms (`?since=&until=` na query, RFC3339): o
workout não sabe nada de timezone, só responde à pergunta com a janela que
recebe — é o `workoutclient.Client` novo do comms
(`internal/workoutclient`, tipos duplicados de propósito, ADR-013 §2) que
resolve "hoje" e chama com `X-Internal-Token`, o mesmo mecanismo M2M já
documentado (`RequireInternalToken`, novo middleware no workout, mesmo
critério do `RequireAuth`/`RequireRole` existentes).

**Verificação:** `gofmt`/`go vet` limpos e todos os testes verdes
(inclusive `-race`) nos dois serviços tocados. No comms: `internal/fcm`
(3 testes de unidade sobre `httptest.Server`, sem rede/credencial real —
sucesso, token morto, erro genérico — mais 2 rejeitando credencial vazia/
inválida), `internal/pubsub` (2 testes novos de presença — marcar/
desmarcar, múltiplas conexões do mesmo usuário), `internal/workoutclient`
(2 testes de contrato HTTP), `internal/job` (2 testes cobrindo o Aceite
literal "job não duplica no mesmo dia" — `Sweep` chamado duas vezes com o
mesmo intervalo só manda push uma vez — e que o dedupe não vaza entre
faixas de dias diferentes; usam Postgres real + `fakePusher`/
`fakeWorkoutSource` em memória, sem bater na Google nem precisar do
workout no ar), `internal/repo` (4 testes novos: upsert de device token
substitui token+locale sem duplicar linha, isolamento cross-tenant de
`ListForUser`, dedupe de `NotificationLogRepo` por faixa/kind — cobre "log
de notificações consultável"), `internal/http` (`devices_test.go`: upsert
por HTTP, validação de plataforma/token/locale/autenticação). No workout:
`internal/repo/pending_test.go` (2 testes: aluno pendente aparece
cross-tenant, aluno que treinou dentro do intervalo não aparece) e
`internal/http/pending_students_test.go` (401 sem/com token errado, 400
com `since`/`until` ausentes ou invertidos, 200 com o Aceite literal sobre
Postgres real).

Smoke manual com `identity`+`workout`+`comms` reais no ar (`FCM_CREDENTIALS_JSON`
já configurada nesta máquina desde o setup do Firebase): `GET
/internal/v1/pending-students` sem token e com token errado devolvem 401,
com o token certo devolve a lista cross-tenant de verdade (dezenas de
alunos de sessões de smoke anteriores, confirmando que a função
`SECURITY DEFINER` realmente atravessa tenants); `POST /v1/devices`
registra um token; o coach manda uma mensagem nova pro aluno (sem WS
aberto) e o log do comms mostra `push_send_failed` com
`"fcm: resposta 400 (INVALID_ARGUMENT)"` — ou seja, a chamada chegou de
verdade na API do Google, autenticada com a credencial real da service
account, e foi recusada só porque o token do device era fake (esperado);
com o comms subindo depois das 18h locais, o job disparou sozinho na
subida e logou `pending_job_sweep_failed` com "connection refused" porque
o workout ainda não estava no ar naquele instante — confirma que a resolução
do timezone (`since`/`until` batendo com meia-noite em
`America/Sao_Paulo`) e o disparo automático do job funcionam.

**Pendente de verificação manual** (fora do alcance desta sessão): o
Aceite "push chega no Android físico/emulador com Play Services" — só dá
pra confirmar com um device de verdade rodando o app Flutter com
`firebase_messaging` (escopo da P3.5, que ainda não existe). Passo a passo
para quando a P3.5 estiver pronta: (1) abrir o app como aluno num Android
com Play Services e deixar `POST /v1/devices` registrar o token real do
FCM; (2) como coach (outro device/sessão), mandar uma mensagem pro aluno
com o app **fechado** (chat) ou registrar um check-in com dor forte (para
o coach); (3) conferir que a notificação chega no Android mesmo com o app
fechado, e que tocar nela abre o app (deep link é escopo da P3.5); (4)
para o job diário, ajustar `NOTIFICATION_TIMEZONE`/o relógio do
device para simular passar das 18h sem ter treinado, e conferir a chegada
de "Treino pendente" uma única vez (repetir no mesmo dia não deve gerar
segunda notificação — o automatizado já cobre a lógica, isto é só a
confirmação visual em device real).

**P3.5:** Flutter — chat, avaliação e notificações. **Fase P3 fechada.**

`core/realtime/` é novo e nasceu de propósito fora de `features/chat/`:
tanto o chat quanto a fila de check-ins do coach (P3.5 §3) precisam do mesmo
WebSocket do `comms` (`GET /ws?token=`), e `docs/guidelines/flutter.md` é
explícito ("feature não importa outra feature; o que for comum sobe para
shared/ ou core/"). `CommsSocketService` só entrega JSON cru decodificado
(`Map<String, dynamic>`, sempre com `type`) — não conhece `ChatMessage` nem
nenhum outro tipo de domínio; cada feature tem seu próprio parser
(`features/chat/data/chat_event.dart` para `message.*`,
`features/checkin/data/checkin_event.dart` para `checkin.pain_strong`), e um
`type` que uma feature não reconhece só devolve `null` em vez de quebrar.
Reconexão com backoff exponencial é o mesmo desenho do `SyncWorker` do P1.7,
adaptado para entrada em vez de fila de saída; `onReconnected` dispara o
resync via REST das telas abertas (Aceite do P3.2: "queda de WS não perde
mensagem"). `commsApiClientProvider` novo em `core/http/providers.dart`,
mesmo padrão dos outros três serviços.

**Chat** (`features/chat/`): `ConversationsController` (lista + soma de não
lidas para o badge da aba) e `ChatMessagesController` (histórico paginado +
envio otimista, por conversa, `autoDispose.family`). Envio otimista não tem
`client_id` de servidor — mensagem não é execução de treino, ADR-003 não
cobre isto — então o dedupe entre a resposta do `POST` e o eco do próprio
evento `message.new` pelo WS (o `comms` publica para os dois participantes,
inclusive o remetente) é só por `id` da mensagem confirmada. Falha de envio
vira estado `failed` na bolha com "tentar de novo"/"remover" — sem fila
offline: chat exige conexão, ADR-003 restringe offline à execução.

Duas decisões fora do texto literal do plano, registradas aqui em vez de
travar a tarefa (mesmo critério do `POST /v1/conversations` da P3.2):
1. **`participant_directory.dart`**: nem `comms` nem o app tinham como
   nomear "o outro participante" de uma conversa — o `comms` só guarda ids
   (ADR-013 §2). Resolvido com duas chamadas a `GET /v1/users` do `identity`
   (papéis `student`/`coach`/`owner`, já existente desde o P1.6) montando um
   mapa id→nome, sem endpoint novo. Não pagina além de 200 por papel — dívida
   da mesma classe do N+1 da lista de alunos (P1.6), aceitável no volume do
   MVP.
2. **Aba Check-ins como quinta aba de `EvolutionScreen`** (P3.5 §3: "aba de
   check-ins na ficha do aluno"): em vez de uma tela nova, virou mais uma aba
   coach-only ao lado do Resumo (P2.5) — mesma tela, mesmo padrão de esconder
   por `scope.isCoach`, badge de pendentes no rótulo (`_CheckinsTabLabel`).
   O aluno nunca vê essa aba: ele registra o check-in pelo bottom sheet
   pós-treino, nunca revisa a própria fila.

**Avaliação pós-treino** (`features/checkin/`): `showCheckinSheet` abre logo
depois de `showSessionSummary` em `SessionPlayerScreen._confirmFinish` —
resumo primeiro, avaliação depois, nunca no lugar um do outro.
`sessionClientId` é o mesmo `client_id` da sessão finalizada (`LocalSession.
clientId`), sem inventar outra chave. `CheckinController.submit` tenta
online primeiro; só em `network_error` grava um rascunho local — não é a
fila `pending_events` do ADR-003 (o plano é explícito: "não: check-in é
online, ADR-003 restringe offline à execução"), é bem mais simples:
`CheckinDraftStorage` guarda uma lista pequena em `flutter_secure_storage`
(reuso do mesmo pacote do `TokenStorage`, sem dependência nova) e
`CheckinController` drena sozinho no boot e a cada volta de conectividade
(`connectivity_plus`, já dependência). Idempotência de verdade continua
sendo do servidor (`session_client_id`), então reenviar o mesmo rascunho
depois de reconectar nunca duplica.

**Badge de não lidas** (P3.5 §1): `LyShellDestination` ganhou `badgeCount`
opcional e `LyShellScaffold` embrulha o ícone num `Badge` do Material 3
quando `badgeCount > 0` — nenhuma dependência nova, o widget já vem com o
Flutter desde a versão pinada deste projeto.

**Push** (`core/push/`, P3.5 §4): `PushService` (permissão, token, upsert em
`POST /v1/devices`, exibição em primeiro plano via `flutter_local_notifications`
— canal `lyfta_push`, separado do `lyfta_rest_timer` do P1.7 — e deep link de
quem tocou a notificação) e `PushProvider` (nasce lendo o `GoRouter` para
saber aonde navegar, se registra sozinho a cada sessão autenticada, mesmo
padrão de autogestão do `commsSocketProvider`). `device_locale.dart` resolve
o locale efetivo do app com `basicLocaleListResolution` (a mesma função que
o `MaterialApp.router` usaria, já que `main.dart` não passa
`localeListResolutionCallback`) em vez do locale cru do sistema — fecha,
só para o registro de device, parte da dívida do P1.8 ("o app não manda
`?locale=`"); o resto do conteúdo dinâmico ainda segue a conta, não a tela.
Tudo isolado atrás de `PushService.isSupported` (`!kIsWeb` +
`defaultTargetPlatform` android/iOS, mesmo guard do `RestTimerService`,
evita `dart:io` que não compila para web) e `try/catch` — sem Firebase
configurado no device, o app sobe normalmente com push desligado, mesmo
critério do `Notifier` do comms sem `FCM_CREDENTIALS_JSON` (P3.4).
Dependências novas, ambas inerentes ao escopo do passo 1/4 do plano
(pré-aprovadas na sessão): `firebase_core`+`firebase_messaging`; e
`web_socket_channel`, que já era transitiva (via outro pacote) e virou
direta.

**Gradle do Android** ganhou o plugin `com.google.gms.google-services`
(`android/settings.gradle.kts` declara a versão, `android/app/build.gradle.kts`
aplica) — é o que processa o `google-services.json`. **Bloqueio conhecido,
não contornado**: o arquivo não existe nesta máquina (só o humano consegue
baixá-lo do Console Firebase, projeto `lyfta-a3bd3`, ver `app/README.md`
§ Firebase) e o plugin recusa configurar o projeto sem ele — todo build
Android fica bloqueado até lá, não só o `firebase_messaging`. Nenhum
placeholder foi commitado; `flutter analyze`/`flutter test` não tocam
Gradle, então a verificação desta tarefa não depende disso.

**Verificação:** `flutter analyze` e o guard de strings limpos, **53 testes
verdes** (7 novos: 5 de `ChatBubble` — lida/não lida/mensagem do outro/envio
em voo/falha com tentar-de-novo-e-remover — e 2 do bottom sheet de check-in
— valores de fábrica sem dor, e nota/dificuldade/dor forte com "onde"
preenchido). O teste da bolha achou um bug de verdade: a linha de ações de
"falha no envio" (texto + tentar de novo + remover) estourava a largura da
bolha num `Row`; virou `Wrap`. `evolution_scope_test.dart` (P2.5) precisou de
três ajustes por causa da aba nova: contagem de abas do escopo do coach
(4→5), `checkinRepositoryProvider` sobrescrito com um fake (senão bateria no
`comms` de verdade) e `commsSocketProvider` também sobrescrito com uma
instância sem `connect()` chamado (senão o `ref.listen(authControllerProvider)`
de dentro dele acionaria o `TokenStorage` real sem platform channel no
teste de widget). Sem backend tocado nesta tarefa — os cinco serviços já
estavam prontos desde a P3.1–P3.4.

**Pendente de verificação manual** (fora do alcance desta sessão, e é o
mesmo roteiro que a P3.4 já deixou escrito): o Aceite literal "fluxo real
entre 2 devices (coach web + aluno Android): mensagem chega via WS, push
chega com app fechado, check-in aparece pro coach" depende de (a) o
`google-services.json` estar em `android/app/` e (b) o app instalado num
Android com Play Services. Passo a passo: (1) coach loga no Chrome, aluno
loga no Android; (2) coach abre o chat do aluno pelo ícone novo na lista de
alunos, manda uma mensagem — confirmar que ela chega no Android via WS sem
precisar puxar para atualizar; (3) fechar o app do aluno, coach manda outra
mensagem — confirmar que a notificação chega pelo FCM e que tocar nela abre
a conversa certa (deep link); (4) aluno termina um treino, preenche o
bottom sheet de avaliação com dor forte — confirmar que o coach recebe o
push imediato mesmo com o app do aluno fechado, e que a avaliação aparece na
aba Check-ins da ficha do aluno com o badge de pendente; (5) derrubar a rede
do aluno no meio de um envio de mensagem/check-in e confirmar o
comportamento de cada um (mensagem falha e oferece tentar de novo; check-in
enfileira local e sai sozinho ao reconectar, com o aviso da tela). iOS segue
fora do escopo desta máquina (Xcode não configurado, ver `STATUS.md`).
