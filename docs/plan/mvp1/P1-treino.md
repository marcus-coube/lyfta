# P1 — Treino (núcleo do produto)

Meta da fase: professor monta um treino A/B/C estruturado com mídia e atribui ao
aluno; aluno abre o **treino do dia**, executa offline registrando carga/reps com
timer de descanso, vê a carga anterior, e tudo sincroniza. É o marco que valida o
produto.

Refs normativas: ADR-003 (offline), ADR-004 (template vs execução), ADR-010
(biblioteca), ADR-011 (traduções de exercício), ADR-013.

---

## - [x] P1.1 Serviço workout — esqueleto + schema completo

**Objetivo:** projeto Go do workout com o modelo do ADR-004 inteiro (o schema nasce
certo; é o coração do sistema).
**Passos:**
1. Bootstrap idêntico ao identity (chi, pgx, migrations, healthz, middleware JWT
   validando com `JWT_PUBLIC_KEY`; middleware `tenant_id` → `SET LOCAL app.tenant_id`).
2. Migrations:
   - `exercises (id, tenant_id nullable — null = global ADR-010, name, primary_muscle,
     equipment, level, media_url, media_type: gif|video, created_by, status)`
   - `exercise_translations (exercise_id, locale, name, instructions)` (ADR-011)
   - `workout_plans (id, tenant_id, student_id, coach_id, title, status)`
   - `workout_plan_versions (id, plan_id, version_no, published_at)` — versões
     imutáveis após publicar
   - `workout_days (id, plan_version_id, label: A|B|C|…, position, title)`
   - `workout_blocks (id, day_id, position, block_type: straight|superset|dropset|
     rest_pause|circuit, rest_seconds)`
   - `block_exercises (id, block_id, exercise_id, position, notes)`
   - `prescribed_sets (id, block_exercise_id, set_no, reps_min, reps_max,
     target_load_kg numeric nullable, target_unit: kg|percent_1rm|rpe|rir,
     target_value numeric nullable, rest_seconds, tempo)` — **estruturado, ADR-012 §4**
   - `student_plan_state (student_id, plan_id, active_version_id, next_day_id,
     last_session_at)` (rotação ADR-004 §3)
   - `workout_sessions (id, tenant_id, student_id, plan_version_id, day_id,
     snapshot jsonb, started_at, finished_at, client_id unique)` — snapshot
     desnormalizado congelado no início (ADR-004 §2)
   - `workout_set_logs (id, tenant_id, session_id, exercise_id, set_no, reps_done,
     load_kg, rpe, logged_at, performed_at, client_id unique, revises uuid null)`
     — append-only (ADR-003)
   - RLS em tudo; exercícios globais legíveis por qualquer tenant (policy dupla).
**Aceite:** migrations sobem/descem limpas; teste de repo grava plano→versão→dia→
bloco→sets e lê de volta; RLS impede leitura cross-tenant em teste.

## - [x] P1.2 workout — mídia (presigned upload)

**Objetivo:** upload de GIF/vídeo de exercício sem passar bytes pelo serviço.
**Passos:** endpoint `POST /v1/media/presign` (auth coach) → URL presigned PUT no
MinIO/S3 (`S3_ENDPOINT`, `S3_BUCKET=lyfta-media`, key
`tenants/{tenant_id}/exercises/{uuid}.{ext}`, contenttype whitelist gif|mp4|webm,
limite 50 MB) + URL pública/presigned GET para exibição.
**Aceite:** teste sobe arquivo pequeno no MinIO local via URL presignada e lê de volta.

## - [x] P1.3 workout — API da biblioteca de exercícios

**Objetivo:** biblioteca global + do tenant (ADR-010) consumível pelo builder.
**Endpoints:** `GET /v1/exercises` (busca por nome no locale do usuário com fallback
pt-PT→pt-BR→en, filtros `muscle`, `equipment`, paginação cursor, globais+do tenant);
`POST/PUT /v1/exercises` (coach; custom do tenant, com `media_url` do P1.2);
`GET /v1/exercises/{id}`.
**Seed:** `backend/workout/seed/exercises_seed.sql` com ~40 exercícios básicos de
musculação (3 locales) para dev/demo — suficiente para montar treinos reais.
**Aceite:** busca em pt-BR encontra exercício global seedado; coach cria exercício
custom que só o próprio tenant vê.

## - [x] P1.4 workout — API do builder e atribuição

**Objetivo:** professor cria/edita plano estruturado e publica para o aluno.
**Endpoints:**
- CRUD de rascunho: `POST /v1/plans` (student_id, título),
  `PUT /v1/plans/{id}/draft` (payload completo dias→blocos→exercícios→sets — edição
  em rascunho substitui a árvore inteira; simples e suficiente pro MVP),
  `GET /v1/plans/{id}` (rascunho ou versão).
- `POST /v1/plans/{id}/publish`: congela `workout_plan_versions` (version_no++),
  atualiza `student_plan_state.active_version_id`, seta `next_day_id` = dia A se
  primeiro publish.
- `GET /v1/students/{id}/plans` (coach) e `GET /v1/me/plan` (aluno).
- Validações: plano sem dia/bloco/set não publica (`422 code:plan_incomplete`);
  só coach do aluno edita.
**Aceite:** fluxo teste: cria plano A/B com sets estruturados → publica → aluno lê
`/v1/me/plan`; editar rascunho e republicar gera v2 sem tocar v1.

## - [ ] P1.5 workout — treino do dia, execução e sync (ADR-003)

**Objetivo:** o contrato offline inteiro do lado servidor.
**Endpoints:**
- `GET /v1/me/today`: resolve `student_plan_state.next_day_id` → retorna snapshot
  do dia (exercícios, mídia, sets prescritos) + **carga anterior** por exercício
  (último `workout_set_log` do aluno por `exercise_id`, ADR-004) + histórico
  recente (últimas 3 sessões resumidas). Payload pensado para cache local integral.
- `POST /v1/sync/workout-logs`: lote de eventos `{client_id, type: session_start|
  set_log|session_finish|set_revision, payload, performed_at}`; idempotente por
  `client_id` (upsert ignora duplicata); resposta lista aceitos/rejeitados; grava
  `received_at` servidor. `session_finish` com ≥1 set → avança rotação
  (`next_day_id` = próximo dia circular, ADR-004 §3).
- `GET /v1/sync/pull?cursor=`: mudanças de plano/biblioteca desde o cursor
  (`updated_at`) para o pull incremental.
- `POST /v1/me/plan/override-day` (aluno ou coach): trocar o próximo dia manualmente.
**Aceite:** reenviar o mesmo lote 2× não duplica logs; sessão concluída avança A→B;
override manual respeitado; teste de carga anterior retorna o último log correto
entre planos diferentes.

## - [ ] P1.6 Flutter — professor: biblioteca e builder mínimo

**Objetivo:** o coach monta o treino no app (web em 1ª classe, mobile funcional).
**Passos:**
1. `features/library/`: lista com busca+filtros, preview de mídia
   (`cached_network_image` p/ GIF; `video_player` p/ vídeo), form de exercício
   custom com upload presigned (P1.2).
2. `features/builder/`: editor de plano — dias (A/B/C, adicionar/reordenar),
   blocos (tipo + descanso), exercícios do bloco (picker da biblioteca), editor de
   sets **estruturado** (linhas: reps min–max, alvo kg|%1RM|RPE|RIR, descanso s) com
   duplicar set/linha. Layout responsivo: master-detail no desktop web, wizard no
   mobile.
3. Publicar com confirmação (mostra nº da versão); lista de alunos do coach
   (identity `GET /v1/users?role=student` — adicionar endpoint se faltar) com plano
   ativo e botão "novo plano".
**Aceite:** no Chrome, coach monta plano A/B com superset e publica; no Android o
mesmo fluxo funciona; teste de widget do editor de sets (adicionar/editar linha).

## - [ ] P1.7 Flutter — aluno: treino do dia offline + execução

**Objetivo:** a experiência-estrela do MVP. Offline-first de verdade (ADR-003).
**Passos:**
1. **Drift** (SQLite): tabelas espelho `today_snapshot` (json do GET /today),
   `pending_events` (fila append-only com client_id uuid v7), `recent_loads`.
   Repositório offline-first: UI lê SEMPRE do banco local; rede só
   hidrata/despacha.
2. Tela **Hoje**: cabeçalho do dia (label A/B/C, título), lista de blocos/
   exercícios com mídia, chip "carga anterior" por exercício; estados: sem plano,
   dia de descanso, offline (banner discreto).
3. **Player de execução**: iniciar sessão (grava `session_start` local) → por
   exercício, marcar set feito (reps + carga, pré-preenchido com prescrição/última
   carga; editável em 2 toques) → ao concluir set dispara **rest timer** (contagem
   do `rest_seconds` do set, notificação local + som + vibração
   `flutter_local_notifications` + `vibration`; funciona com app em background) →
   finalizar sessão (resumo: volume total, sets feitos, duração; grava
   `session_finish`).
4. **Sync**: worker que drena `pending_events` em lotes para `/v1/sync/workout-logs`
   com retry exponencial + trigger em reconexão (`connectivity_plus`); pull do
   `/v1/me/today` ao abrir com rede; indicador sutil de pendências no app bar.
5. Correção de registro: editar um set já logado gera evento `set_revision`
   (`revises: client_id` — ADR-003 §5), nunca update.
**Aceite (roteiro manual obrigatório):** com o device em modo avião, abrir treino
já baixado, executar 2 exercícios com timer tocando/vibrando, fechar o app, religar
a rede → logs aparecem no banco do servidor sem duplicatas; teste unitário da fila
(enqueue/drain/retry/idempotência).

## - [ ] P1.8 Rotação e integração ponta a ponta

**Objetivo:** fechar o loop A→B→C e validar o marco da fase.
**Passos:** ao `session_finish` sincronizado, o próximo `GET /today` traz o dia
seguinte; UI do aluno mostra "próximo treino: B"; opção "trocar treino de hoje"
(override, P1.5). Roteiro E2E documentado em `docs/plan/mvp1/e2e-p1.md`: signup →
convite → aluno entra → coach publica A/B → aluno executa A offline → sync → hoje
vira B.
**Aceite:** roteiro E2E executado nas 3 plataformas-alvo (web coach + Android aluno
mínimo); bugs achados viram tarefas na seção Notas.

---

## Notas de execução

(o agente anota aqui descobertas, dívidas e desvios aprovados)

### P1.1 (2026-08-27, Mac)

- **Serviço `workout`** (`backend/workout`, porta 8082, banco `lyfta_workout`)
  com o mesmo bootstrap do identity: chi + pgxpool + slog, `/healthz`,
  middlewares (request-id, logging estruturado, recover, CORS) e 13 migrations.
  `go.mod` próprio com a stack pinada do `backend/README.md` — nada importado
  do identity (ADR-013 §2); `internal/security` é irmão duplicado de propósito
  e ficou **só com validação** (`JWTVerifier`): a chave privada que assina é
  exclusividade do identity (ADR-013 §4), então `config` exige
  `JWT_PUBLIC_KEY` e nem lê `JWT_PRIVATE_KEY`.
- **Sem FK cruzando banco:** `student_id`, `coach_id` e `created_by` apontam
  para `users.id` do identity e por isso são UUID solto, sem `REFERENCES`
  (ADR-013 §2). Só as FKs intra-banco existem (versão→plano, dia→versão,
  bloco→dia, `block_exercises`→`exercises`). Este banco **não tem tabela
  `tenants`** — nos testes o tenant é um UUID qualquer, exatamente como
  chegaria numa claim.
- **`tenant_id` em toda tabela, inclusive nas filhas** (`workout_days`,
  `workout_blocks`, `block_exercises`, `prescribed_sets`), embora o plano só
  liste as colunas de negócio: ADR-001 §1/§3 é normativo e uma policy direta
  por `tenant_id` é mais barata que um `EXISTS` subindo a árvore a cada linha.
- **Policy dupla dos exercícios (ADR-010 §3):** `SELECT` enxerga o global
  (`tenant_id NULL`) e o do próprio tenant; `INSERT/UPDATE/DELETE` só aceitam
  linhas do próprio tenant. Consequência deliberada: **a aplicação não
  consegue criar exercício global** — a biblioteca global entra por seed
  administrativo (superusuário), e há teste garantindo essa recusa.
  `exercise_translations` carrega `tenant_id` espelhado do exercício para a
  policy decidir sem join.
- **Imutabilidade garantida no banco, não só na aplicação** (migration 0012,
  o desvio mais relevante desta tarefa): triggers recusam (a) escrita em
  versão publicada e em toda a sua árvore — publicar é o último `UPDATE` que
  a versão aceita (ADR-004 §1) — e (b) `UPDATE`/`DELETE` em
  `workout_set_logs`, que é append-only (ADR-003 §2); corrigir é inserir
  outro log com `revises`. Sem isso, "o histórico do aluno é imutável" seria
  só uma convenção de handler. Efeito colateral aceito: apagar um plano
  publicado passa a ser impossível via cascade — arquiva-se
  (`status='archived'`).
- **Prescrição estruturada (ADR-012 §4)** com ponteiros no domínio para
  separar "não prescrito" de zero: 0 kg é carga válida (peso corporal), NULL
  é ausência de prescrição. `CHECK` garante `reps_max >= reps_min` e alvo
  relativo (%1RM/RPE/RIR) sempre com valor.
- **`client_id` é único por tenant** (`UNIQUE (tenant_id, client_id)`), não
  global: o índice começa por `tenant_id` como manda o ADR-001 §3, e a
  idempotência do push offline (ADR-003 §4) continua valendo dentro do
  escopo em que o device opera.
- **Tenant vem da claim, sempre.** O plano pedia "middleware `tenant_id` →
  `SET LOCAL app.tenant_id`"; implementado como no identity: `RequireAuth`
  injeta as claims e `repo.WithTenant` seta `app.tenant_id` na transação.
  `SET LOCAL` só vale dentro de transação — um middleware HTTP teria de
  segurar uma conexão do pool pela requisição inteira para o mesmo efeito.
  `RequireAuth` também recusa token válido **sem** `tenant_id`: sem tenant não
  há escopo de RLS. `GET /v1/whoami` existe como sonda autenticada até as
  rotas de negócio chegarem (P1.2–P1.5).
- **Verificado (Mac):** `migrate up` → `down -all` → `up` limpos (schema volta
  a ter só `schema_migrations`, nenhuma função órfã) — o `down` do
  `0013_app_role` revoga privilégios mas **não** dropa a role, diferente do
  identity, porque `lyfta_app` é compartilhada entre os bancos e dropá-la
  quebraria o identity. `go vet` limpo e 8 testes verdes (5 de repo: árvore
  plano→versão→dia→bloco→exercício→sets com round-trip campo a campo,
  isolamento cross-tenant nos dois sentidos, recusa de exercício global,
  imutabilidade da versão publicada, append-only dos logs; 3 de handler:
  `/healthz` público, `/v1/whoami` feliz e 5 casos de token inválido). O
  fluxo do CI foi reproduzido em Postgres 17 limpo em Docker (banco novo,
  role criada pela migration, testes verdes). **Integração real entre
  serviços confirmada:** `identity` e `workout` subidos juntos, signup no
  identity via `curl` e o `access_token` resultante aceito pelo
  `/v1/whoami` do workout só com a chave pública — devolveu o mesmo
  `tenant_id`/`roles` da claim.
- **Anotações para as próximas tarefas (não implementadas aqui):**
  `workout_set_logs` não tem `student_id` desnormalizado — o plano lista as
  colunas sem ele, então a consulta de "carga anterior" (P2, gráfico de
  carga) vai precisar de join com `workout_sessions`; se doer, é uma
  migration de desnormalização. A taxonomia do ADR-010 §4 entrou parcial
  (músculo primário, equipamento, nível): `movement_pattern` e a tabela
  `exercise_muscles` com `effort_pct` são insumo do muscle map, que não está
  no MVP 1.0. `student_plan_state` tem uma linha por aluno
  (`PRIMARY KEY (tenant_id, student_id)`): trocar de plano sobrescreve o
  estado, sem histórico de planos anteriores — suficiente para a rotação do
  ADR-004 §3.

### P1.2 (2026-08-27, Mac)

- **Dependência nova aprovada pelo fundador nesta sessão: `aws-sdk-go-v2`**
  (`service/s3` + `credentials`), registrada na stack pinada do
  `backend/README.md`. Contexto da escolha: a intenção declarada é usar
  **Cloudflare R2** em produção, e o SDK que a própria Cloudflare documenta
  para R2 é este — "aws-sdk" aqui é o nome da biblioteca, não o fornecedor.
  Alternativas descartadas: `minio-go` (uma dependência a menos, mas amarra a
  mídia a uma lib mantida pela MinIO) e SigV4 escrito à mão (assinatura
  própria para manter, com falha típica em 403 opaco).
- **Nada de código muda ao sair do MinIO** (ADR-009 já previa): a troca é
  `S3_ENDPOINT`, `S3_USE_PATH_STYLE` (path-style no MinIO e no endpoint de
  conta do R2; `false` para S3 por subdomínio) e `S3_PUBLIC_BASE_URL`. Esta
  última é a que decide a `media_url`: **vazia** → GET assinado que expira
  (bucket privado, o caso do MinIO de dev); **preenchida** com o domínio
  público/CDN → URL direta e permanente, que é como o R2 costuma servir mídia
  atrás do CDN. Sem esse par de chaves, a migração exigiria mexer no handler.
- **O limite de 50 MB é garantia do storage, não promessa do cliente:**
  `PresignPut` assina `Content-Type` **e** `Content-Length`, então a URL só
  aceita exatamente aquele arquivo. Verificado: subir 4096 bytes numa URL
  assinada para 1024 dá **403**, e trocar o content-type também. Se o tamanho
  não entrasse na assinatura, a URL seria um upload livre de qualquer coisa
  até expirar. Custo: o app precisa saber o tamanho antes de pedir a URL —
  aceitável, o arquivo já está no device.
- **Chave `tenants/{tenant_id}/exercises/{uuid}.{ext}`** com o tenant vindo da
  **claim**, nunca do body: token do tenant A não assina upload na pasta do
  tenant B. O particionamento por tenant também torna trivial exportar ou
  apagar a mídia de um cliente (ADR-008/LGPD).
- **Endpoint restrito a `owner|coach`** (ADR-010 §3: quem sobe mídia é o
  professor). TTL das URLs: 15 min — curto para um link vazado não virar
  upload livre, longo para 50 MB numa conexão ruim.
- **CI:** o job `backend` ganhou um step que sobe MinIO via `docker run`,
  condicional a `matrix.service == 'workout'` (`services:` do Actions não
  aceita condicional nem comando customizado, e a imagem do MinIO precisa de
  `server /data`). O bucket é criado pelo próprio teste, então o CI não
  depende do `minio-init` do compose. Os testes de mídia pulam sem MinIO fora
  do CI e **falham** dentro dele, mesmo padrão do banco no P0.7.
- **Verificado (Mac):** `go vet` limpo, 12 testes verdes no workout (4 novos de
  mídia + 4 de handler de presign + os do P1.1). Aceite exercitado de duas
  formas: teste de integração subindo um GIF real no MinIO pela URL assinada e
  lendo os mesmos bytes de volta (com content-type preservado), **e**
  manualmente ponta a ponta com os dois serviços no ar — signup no `identity`
  via `curl`, `POST /v1/media/presign` no `workout` com o token do coach,
  `PUT` do arquivo (200), download pela `media_url` (200, bytes idênticos) e
  `PUT` com tamanho diferente do assinado (403). O `docker compose up -d`
  (Redis + MinIO) foi executado e ficou **healthy nesta máquina** — resolve no
  Mac a verificação que estava pendente desde o P0.1; no Windows continua em
  aberto (sem Docker lá).
- **Anotações para as próximas tarefas:** `media.KeyFromURL` já existe para o
  P1.3, quando o coach devolver a `media_url` no cadastro do exercício e o
  serviço precisar saber qual objeto ela aponta. Não há **coleta de lixo** de
  objetos órfãos: presign que nunca vira exercício deixa arquivo no bucket —
  vale um job de limpeza (ou verificação de existência no P1.3) antes de
  produção. `S3_PUBLIC_BASE_URL` não valida se o bucket é mesmo público: se
  for preenchida com bucket privado, a mídia quebra silenciosamente na UI.

### P1.3 (2026-08-27, Mac)

- **Taxonomia virou código estável, não rótulo** (`internal/domain/library.go`):
  `primary_muscle` e `equipment` passaram a ser `chest`/`barbell`, validados no
  handler contra a lista do ADR-010 §4. Quem traduz para "peitoral"/"barra" é o
  app — string de UI nascendo no backend é exatamente o que o ADR-011 §5
  proíbe, e filtro que volta lista vazia por causa de grafia é bug caro. Filtro
  fora da taxonomia responde `400 validation_error`, não lista vazia. O
  `seedExercise` do `repo_test` do P1.1 foi migrado para os códigos.
- **Fallback de locale nos dois lados** (ADR-011 §2): na listagem é `LEFT JOIN
  LATERAL` com `array_position` sobre a cascata (uma tradução por exercício,
  escolhida no banco); no detalhe é a mesma cascata em Go sobre as traduções já
  carregadas. A cascata foi **generalizada**: locale pedido primeiro, depois
  pt-BR → pt-PT → en. Para pt-PT dá a ordem normativa do ADR; para os outros a
  regra é preferir português antes de inglês. Último recurso é a coluna
  `exercises.name` (língua-fonte), então exercício sem tradução nenhuma —
  o custom que o coach cria em dois campos — nunca aparece sem nome. A resposta
  devolve `locale`, o idioma que **de fato** saiu, para o cliente saber que
  caiu no fallback.
- **Busca ignora acento e caixa** (migration 0014, `lyfta_search_norm`): quem
  digita "triceps" tem de achar "Tríceps testa". Feita com `translate()`
  IMMUTABLE em vez da extensão `unaccent` — extensão exige superusuário para
  instalar (dev, CI e Postgres gerenciado) e `unaccent()` é STABLE, logo não
  indexável. A busca cobre o nome exibido **e** o canônico: com a UI em pt-PT
  mostrando "Peso morto", procurar "levantamento terra" continua achando.
- **Paginação keyset** por `(nome normalizado, id)` com cursor opaco em
  base64 — estável quando entra exercício novo no meio da lista, ao contrário
  de OFFSET. `limit` default 30, teto 100; cursor corrompido é
  `400 invalid_cursor`.
- **Mídia amarrada ao tenant nos dois sentidos:** na escrita, `media_url` é
  recusada se não apontar para `tenants/{claim}/…` (`Presigner.KeyForTenant`) —
  é o par do presign do P1.2, que já derivava o caminho da claim; na leitura,
  a URL é **assinada de novo** (`Presigner.ResolveURL`), porque em bucket
  privado o que está gravado é uma assinatura que já expirou. Com
  `S3_PUBLIC_BASE_URL` (R2 em produção) a renovação é no-op e a URL gravada é a
  permanente. Verificado ponta a ponta: presign → PUT → cadastro → leitura →
  download 200.
- **Global é somente leitura, e a API diz isso:** `PUT` num exercício global
  responde `403 exercise_is_global`, não 404. O RLS recusaria de qualquer jeito,
  mas "não existe" é resposta errada para um exercício que o professor está
  vendo na tela. **Clonar** (ADR-010 §3) não ganhou endpoint próprio: é `GET` +
  `POST` no cliente. Se virar atrito no P1.6, vale um `POST
  /v1/exercises/{id}/clone`.
- **Arquivar em vez de apagar:** `status='archived'` some da biblioteca e não há
  `DELETE` — exercício pode estar referenciado por versão publicada, que é
  imutável (P1.1).
- **Seed: 41 exercícios globais × 3 locales** (`seed/exercises_seed.sql`), com
  os básicos de academia (peito/costas/ombro/braço/perna/panturrilha/abdômen).
  **Não é migration** — é conteúdo, não schema — e roda como superusuário,
  porque nenhuma policy de escrita cobre `tenant_id NULL` (decisão do P1.1):
  `psql -U postgres -d lyfta_workout -f backend/workout/seed/exercises_seed.sql`.
  Id determinístico (`md5(slug)`) + `ON CONFLICT DO UPDATE` deixam o arquivo
  reexecutável a cada correção de texto, com o mesmo UUID em toda máquina. O CI
  ganhou o step de seed no job do workout (os testes de biblioteca dependem
  dele: pulam sem seed fora do CI, **falham** dentro dele — mesmo padrão do
  banco no P0.7).
- **Verificado (Mac):** `go vet` limpo, **26 testes verdes** (14 novos: 6 de
  repo — busca acentuada no global do seed, cascata pt-PT→pt-BR, isolamento
  entre bibliotecas de tenants, filtro+paginação completa, recusa de edição de
  global, upsert de tradução e arquivamento; 8 de handler cobrindo o Aceite
  pela API, 403 no global, aluno lê mas não escreve, e 8 casos de validação).
  Migration 0014 sobe e desce limpa; seed rodado 2× sem duplicar. **Smoke
  manual ponta a ponta:** `identity` + `workout` no ar, signup com
  `locale=pt-PT`, e o token real trouxe a biblioteca já em português europeu
  sem nenhum parâmetro — `?locale=en` sobrescreve.
- **Anotações para as próximas tarefas:** a meta de ~300 exercícios curados do
  ADR-010 §5 continua aberta (estes 41 são para dev/demo/MVP); os globais **não
  têm mídia** e a coluna `exercise_media.source_license` do ADR-010 §1 não
  existe no schema — entra quando a curadoria com GIF começar, junto da
  importação da base aberta. A busca faz seq scan (`LIKE '%x%'` não usa btree):
  irrelevante em 300 linhas, resolvível com `pg_trgm` quando doer. Continua sem
  coleta de lixo de mídia órfã (anotado no P1.2): agora dá para cruzar objetos
  do bucket com `exercises.media_url`.

### P1.4 (2026-08-28, Mac)

- **O rascunho é que gera a versão, não o publish.** O plano dizia
  "`publish` congela a versão (version_no++)"; implementado com o `++`
  acontecendo antes: `PUT /draft` abre a versão seguinte quando a última já
  está publicada, e `publish` só carimba `published_at`. Vale a pena porque a
  tela do coach passa a mostrar "rascunho da v2" enquanto edita, e porque a
  imutabilidade continua vindo do banco (trigger da 0012): a v1 é intocável
  desde o instante em que foi publicada, sem depender de o handler lembrar
  disso. `POST /v1/plans` **não** cria versão nenhuma — plano recém-criado
  volta com `version: null` e ganha a v1 no primeiro salvamento.
- **`PUT /draft` substitui a árvore inteira** (DELETE dos dias, que cascateia
  até os sets, + INSERT), como o plano previa. Position de dia/bloco/exercício
  e `set_no` saem da **ordem do array** enviado, não de índices do cliente:
  reordenar é mover item na lista, e não há como chegar buraco ou posição
  duplicada. `FOR UPDATE` no plano serializa dois coaches salvando junto.
- **`exercise_id` é validado sob RLS, e isso não é preciosismo:** a verificação
  de FK do Postgres roda com os privilégios do dono da tabela e **ignora RLS**,
  então `block_exercises.exercise_id` sozinho aceitaria o UUID de um exercício
  de outro tenant. `assertExercisesVisible` faz o `SELECT` dentro da transação
  com `app.tenant_id` setado e devolve `422 unknown_exercise` com o id
  recusado. Tem teste nos dois níveis (repo e handler).
- **Erros novos:** `422 plan_incomplete` com `reason`
  (`no_days` | `day_without_block` | `block_without_exercise` |
  `exercise_without_set`) e `day_id` — o coach precisa saber *qual* dia ficou
  vazio, não só que o plano não publica; `409 no_draft_to_publish` ao publicar
  duas vezes seguidas (publicar sem rascunho não gera versão nova);
  `422 unknown_exercise`. Validação de payload devolve
  `validation_error` com o caminho do campo
  (`days[0].blocks[1].exercises[0].sets[2].reps_max`).
- **"Só coach do aluno edita" virou "coach dono do plano ou owner".** O vínculo
  coach↔aluno vive no `identity` e este serviço não tem como consultá-lo (não
  existe endpoint service-to-service para isso ainda, e `X-Internal-Token`
  sozinho não resolve). O proxy disponível é a autoria: `workout_plans.coach_id`
  contra o `sub` da claim, com o owner sempre podendo. **Ler** é do tenant
  inteiro — um professor cobrindo férias do outro tem de abrir o plano.
  Dívida anotada para quando o identity expuser o vínculo.
- **`student_id` não é verificado contra o identity:** criar plano para um UUID
  que não existe é aceito. Consequência conhecida da separação de bancos
  (ADR-013 §2); o P1.6 vai listar os alunos pelo identity, então na prática o
  id chega de uma lista real. Validar de verdade exige chamada síncrona entre
  serviços — fica para quando doer.
- **Rotação (ADR-004 §3):** primeiro publish aponta `next_day_id` para o
  primeiro dia; republicar o **mesmo** plano preserva o dia pelo **rótulo** —
  quem estava no B continua no B depois de o coach corrigir uma carga. Se o
  rótulo sumir na versão nova, cai no primeiro dia. Publicar um plano
  **diferente** para o aluno arquiva o anterior (`status='archived'`):
  `student_plan_state` tem uma linha por aluno (PK do P1.1), então "dois planos
  publicados" não é um estado representável.
- **Bug do P1.1 achado pelo smoke, não pelos testes:** `GetVersionTree`
  remontava a árvore guardando **ponteiro** para elemento de slice
  (`&day.Blocks[len-1]`); o `append` do irmão seguinte realocava o array e o
  ponteiro antigo passava a apontar para a cópia velha — resultado: bloco com
  dois exercícios perdia os sets do primeiro. Os testes do P1.1/P1.4 não
  pegaram porque usavam um exercício por bloco. Corrigido com índices em vez de
  ponteiros, e `TestVersionTreeWithSiblings` cobre o caso (2 blocos, 3
  exercícios, sets diferentes em cada).
- **A árvore volta com o exercício resolvido** (`exercise`: nome no locale,
  mídia re-assinada, músculo/equipamento, `is_global`) — sem isso o builder e a
  tela do aluno precisariam de uma segunda chamada à biblioteca por exercício.
  É uma consulta só para a árvore inteira (`ExerciseRepo.ByIDs`), com a mesma
  cascata de locale do P1.3 e **sem** filtro de status: exercício arquivado
  depois de entrar no plano continua aparecendo no plano.
- **Verificado (Mac):** `go vet` limpo, **37 testes verdes** (11 novos: 6 de
  repo — publicar/editar gerando v2 com a v1 intacta, rotação preservada por
  rótulo, os 4 níveis de `plan_incomplete` + publish sem rascunho, recusa de
  exercício de outro tenant, isolamento de plano/estado/lista entre tenants e a
  regressão da árvore; 5 de handler cobrindo o Aceite inteiro pela API,
  republicação, `plan_incomplete`/`no_draft_to_publish`, controle de acesso
  (outro tenant 404, outro coach 403, aluno 403, aluno sem plano 404) e 9 casos
  de validação de payload). **Smoke manual ponta a ponta** com os dois serviços
  no ar: signup do coach → convite → aceite do aluno → `POST /v1/plans` →
  `PUT /draft` A/B (superset com 2 exercícios, alvos em kg, RPE e %1RM) →
  `publish` → aluno lendo `GET /v1/me/plan` com o token dele e locale pt-PT →
  edição virando v2 com dia C → `GET ?version=1` mostrando a v1 congelada com a
  carga antiga → segundo `publish` recusado com `no_draft_to_publish`.
- **Anotações para as próximas tarefas:** não há `DELETE /v1/plans/{id}` nem
  como descartar um rascunho — arquivar é o caminho, e "descartar rascunho"
  vira `PUT /draft` com `days: []`. `GET /v1/plans/{id}` faz várias consultas
  curtas (plano, versões, estado, árvore, exercícios) em transações separadas;
  irrelevante no tamanho de um plano, mas é o endpoint que o P1.5 vai
  reaproveitar para o `GET /v1/me/today`, onde entra também a carga anterior. A
  lista de alunos do coach continua no identity (P1.6 precisa dela).
