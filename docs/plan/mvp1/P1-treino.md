# P1 — Treino (núcleo do produto)

Meta da fase: professor monta um treino A/B/C estruturado com mídia e atribui ao
aluno; aluno abre o **treino do dia**, executa offline registrando carga/reps com
timer de descanso, vê a carga anterior, e tudo sincroniza. É o marco que valida o
produto.

Refs normativas: ADR-003 (offline), ADR-004 (template vs execução), ADR-010
(biblioteca), ADR-011 (traduções de exercício), ADR-013.

---

## - [ ] P1.1 Serviço workout — esqueleto + schema completo

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

## - [ ] P1.2 workout — mídia (presigned upload)

**Objetivo:** upload de GIF/vídeo de exercício sem passar bytes pelo serviço.
**Passos:** endpoint `POST /v1/media/presign` (auth coach) → URL presigned PUT no
MinIO/S3 (`S3_ENDPOINT`, `S3_BUCKET=lyfta-media`, key
`tenants/{tenant_id}/exercises/{uuid}.{ext}`, contenttype whitelist gif|mp4|webm,
limite 50 MB) + URL pública/presigned GET para exibição.
**Aceite:** teste sobe arquivo pequeno no MinIO local via URL presignada e lê de volta.

## - [ ] P1.3 workout — API da biblioteca de exercícios

**Objetivo:** biblioteca global + do tenant (ADR-010) consumível pelo builder.
**Endpoints:** `GET /v1/exercises` (busca por nome no locale do usuário com fallback
pt-PT→pt-BR→en, filtros `muscle`, `equipment`, paginação cursor, globais+do tenant);
`POST/PUT /v1/exercises` (coach; custom do tenant, com `media_url` do P1.2);
`GET /v1/exercises/{id}`.
**Seed:** `backend/workout/seed/exercises_seed.sql` com ~40 exercícios básicos de
musculação (3 locales) para dev/demo — suficiente para montar treinos reais.
**Aceite:** busca em pt-BR encontra exercício global seedado; coach cria exercício
custom que só o próprio tenant vê.

## - [ ] P1.4 workout — API do builder e atribuição

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
