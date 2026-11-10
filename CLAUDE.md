# Lyfta — contexto do projeto

SaaS multi-tenant de gestão de treino para academias, personais e estúdios (BR).
App único Flutter (Android/iOS/Web responsivo) + backend Go. Dev **solo, full-time,
com assistência de IA**. Este arquivo é o contexto compartilhado entre máquinas
(Windows + Mac) — versionado no git; a pasta `~/.claude` **não** sincroniza.

## Stack
Flutter (front) · Go em **microserviços com banco Postgres por serviço** (ADR-013) ·
Redis · S3-compatible (MinIO no dev) · WebSockets · Auth JWT EdDSA + refresh ·
E-mail transacional via **Resend**. Idiomas pt-BR / pt-PT / en desde o lançamento (ADR-011).

## Mapa do repositório
- `app/` — app Flutter. Só `lib/`, `pubspec.yaml` e configs são versionados; gerar
  plataformas com `flutter create .` (ver [app/README.md](app/README.md)).
  - `lib/core/design_system/` — tokens, tema e componentes `Ly*` (fonte de verdade do DS).
  - `lib/features/` — features por domínio (`auth/` = login visual, único hoje).
- `backend/` — microserviços Go: `identity` (8081), `workout` (8082),
  `assessment` (8083), `comms` (8084) e `billing` (8085, 2.0) existem. Stack pinada, portas e bancos em
  [backend/README.md](backend/README.md). Futuro: cada serviço em repo próprio —
  **nunca** importar código entre serviços (duplicar é o certo: ver o
  `internal/security` de cada um).
- `docs/` — documentação. **Fonte de verdade de produto e arquitetura.**
- `.claude/agents/mvp-dev.md` — agente (Sonnet) que executa os planos do MVP
  (1.0 e 2.0), uma tarefa por invocação.

## Onde está a verdade (ler antes de propor mudanças)
- **[docs/000-product_description.md](docs/000-product_description.md)** — roadmap em
  **pacotes** (MVP 1.0 → 2.0 → 3.0 → 4.0 running → V2 IA → Futuro).
- **[docs/014-plano-de-documentacao.md](docs/014-plano-de-documentacao.md)** — plano de
  docs + marcos de implementação e de-para marco→pacote.
- **[docs/adr/](docs/adr/)** — decisões estruturais (ADR-001..018). São normativas.
- **[docs/plan/mvp1/](docs/plan/mvp1/)** — plano de execução do MVP 1.0 (P0–P4,
  32 tarefas, protocolo do agente). Fechado; lista pré-loja (L1–L10) no `STATUS.md`.
- **[docs/plan/mvp2/](docs/plan/mvp2/)** — plano do MVP 2.0 (P5–P8, 19 tarefas):
  alunos, builder completo, financeiro só com baixa manual, dashboard. Progresso
  em `STATUS.md`.
- **[docs/benchmarking/](docs/benchmarking/)** — auditoria HubFit × Trainerize × Lyfta.
- `docs/guidelines/` — convenções de código (ex.: `flutter.md`).

## Estado atual (2026-11-09)
**Executando o plano do MVP 2.0** ([docs/plan/mvp2/](docs/plan/mvp2/)) na ordem
P5→P8, uma tarefa por vez via agente `mvp-dev` (comando: "implemente P5.X").
**Progresso vivo em [STATUS.md](docs/plan/mvp2/STATUS.md)** — ler ele primeiro para
saber a próxima tarefa; pendências por tarefa nas "Notas de execução" da fase.
**MVP 1.0 fechado: P0–P4 concluídas, 32/32 (2026-11-08):** `identity` completo (auth, convites,
reset, lista de usuários do tenant), CI no GitHub Actions
(`.github/workflows/ci.yml`) e o serviço `workout` completo do lado servidor —
schema do ADR-004, mídia por URL presignada, biblioteca com seed global de 41
exercícios em 3 locales, builder versionado e o contrato offline do ADR-003
(treino do dia, push idempotente da fila, pull incremental, rotação A→B→C)
(P1.1–P1.5). No app Flutter, o **professor** tem biblioteca e builder completo
(P1.6) e o **aluno** tem o treino do dia offline: banco local por plataforma
(SQLite via drift no celular, memória na web — ver Notas do P1.7), tela Hoje
com carga anterior, player com timer de descanso e correção append-only, e
worker que drena a fila com backoff e reconexão (P1.7). O loop A→B→C fecha
ponta a ponta: o roteiro E2E de [e2e-p1.md](docs/plan/mvp1/e2e-p1.md) foi
executado nos 22 passos com coach no Chrome e aluno em emulador Android com a
rede cortada de verdade (P1.8) — é o teste de fumaça a repetir antes de cada
release. No P2, o `workout` já serve o histórico por exercício que vira o
gráfico de carga (P2.1), o serviço `assessment` serve medidas, bioimpedância
digitada e fotos (P2.2/P2.3) e a fase fechou com aluno e professor vendo a
mesma tela Evolução — gráfico de carga (`fl_chart`), medidas e bioimpedância
com deltas, fotos com comparador antes/depois —, parametrizada por
`EvolutionScope` (`me()` ou `student(id)`), com a aba Resumo a mais no lado do
professor (P2.4/P2.5). **A P3 (comunicação) está fechada**: o quinto serviço,
`comms`, serve chat (REST com cursor e não lidas, imagem por presign,
`GET /ws?token=` com fan-out entre instâncias pelo Redis, P3.1/P3.2),
check-in de treino idempotente por sessão com a fila do coach ordenada por
não revisados (P3.3) e push FCM + job diário de treino pendente (P3.4). No
app, `features/chat/` (lista de conversas com badge de não lidas, conversa
direta com envio otimista texto/imagem, reconexão de WS transparente) e
`features/checkin/` (bottom sheet pós-treino com rascunho local se a rede
cair, fila de check-ins como aba do coach na ficha de evolução) fecham a
comunicação dos dois lados, com `core/push/` registrando o device e abrindo a
notificação tocada no lugar certo (P3.5) — pendente de verificação manual em
Android físico enquanto o `google-services.json` não é baixado do Console
Firebase (bloqueio conhecido, ver `app/README.md` § Firebase). Na P4, o
`workout` ganhou `GET /v1/me/sessions?from=&to=` e o aluno tem a aba
**Agenda**: strip semanal (dom–sáb) com o que já foi treinado e o que a
rotação projeta localmente para os próximos dias, mês expansível e streak
simples de semanas seguidas batendo a meta (P4.1).
P4.2 (performance) e P4.3 (i18n + acessibilidade) fechadas; a P4.4 (E2E final)
fechou com o [e2e-final.md](docs/plan/mvp1/e2e-final.md) executado no Android e
aceito pelo usuário sem execução completa no iOS e no aluno web. A **P4.5 (LGPD mínima,
ADR-008) fechou**: consentimento versionado (`consents` no identity, finalidades
`terms`/`health_data`/`progress_photos` nas claims do JWT, gate `/consent` no
app, textos em `app/assets/legal/` com `TERMS_VERSION`), tela Conta
(privacidade, sair, excluir conta) e `DELETE /v1/me`, que orquestra a exclusão
nos outros serviços via `DELETE /internal/v1/users/{id}` (exclusão física de
saúde/fotos, anonimização de execuções e mensagens) — falta só a revisão
jurídica dos textos (humano). A **P4.6** fechou o relato de
erros (Sentry/GlitchTip, ADR-009 §5): `sentry_flutter` no app e `sentry-go` nos 4
serviços, DSN vazio = desligado, evento só com `user_id`/`tenant_id` — falta só
o projeto com DSN (humano). A **P4.7** fechou o vínculo professor↔aluno
(ADR-016, ADR-008 §3): tabela `coach_students` no identity (1 coach por aluno,
nasce no convite, owner reatribui), checagem por M2M com cache de 30 s no
`internal/coachlink` de workout, assessment e comms, e 404 `student_not_found`
para aluno que não é do coach — owner vê tudo, e só ele troca o professor no app.
**MVP 2.0** — plano em [docs/plan/mvp2/](docs/plan/mvp2/README.md)
(P5 alunos → P6 builder → P7 financeiro → P8 dashboard/release). **P5 fechada
(5/5, 2026-11-09):** fuso do tenant (claim `tz`, job de pendente por fuso),
cadastro e ciclo de vida do aluno no identity (`/v1/students`, status
`inactive` com histórico, M2M de status em lote; coach só convida aluno),
anamnese e lesões no assessment com `health_data` exigido em medidas,
bioimpedância e anamnese (meta semanal só do coach), e no app a lista de
alunos paginada com "último treino" (`POST /v1/students/overview` no
workout), ficha `/students/:id` (Dados/Treino/Evolução/Check-ins), "Meus
dados" e "Meu objetivo" do aluno. Ninguém usa o app ainda: contratos podem
mudar em vez de acumular dívida. **P6 fechada (5/5, 2026-11-10):** (modelos e ciclo de vida no `workout`; no app, aba Modelos, aplicar/reaplicar em lote e ficha com Aplicar modelo/Duplicar/Arquivar/Ativar, arquivado somente leitura; builder com reordenar por alça, duplicar dia/bloco, histórico de versões e próximo dia; player por bloco: bi-set/circuito conduzidos por rodada e dropset/rest-pause encadeados, via `BlockRunner`). **P7.1–P7.4 prontas** (14/19): `billing` (8085, `lyfta_billing`) com schema do ADR-007 + RLS e a API do financeiro (planos, assinaturas, faturas, baixa manual idempotente, estorno, status derivado, `/me/invoices`, matriz owner/coach `own_students`/`status_only`) e o job mensal (tick de 15 min com advisory lock: gera a fatura do mês e vence as abertas no fuso de cada tenant). No app, a aba Financeiro (owner e coach `own_students`: faturas, baixa, estorno, planos), a aba Financeiro da ficha, o selo "inadimplente", o toggle da Organização e "Minhas mensalidades" do aluno (P7.4). Próximo: P7.5 (exclusão de conta com financeiro). Financeiro do 2.0 é o sexto serviço, `billing`, **só
com baixa manual** — PIX adiado; acesso do coach configurável por organização ([ADR-017](docs/adr/ADR-017-financeiro-servico-billing-baixa-manual.md));
modelos de treino aplicados por cópia ([ADR-018](docs/adr/ADR-018-modelos-de-treino-por-copia.md)).
Tudo só em emulador: o que depende de
loja, conta ou aparelho virou a lista **pré-loja** (L1–L10 do STATUS) — Android
compila sem `google-services.json` (sem push). iOS roda no
simulador com Xcode 27 (receita em [app/README.md](app/README.md) § iOS). Escopo do MVP em
[ADR-012](docs/adr/ADR-012-escopo-mvp-packs.md); arquitetura de serviços em
[ADR-013](docs/adr/ADR-013-microservicos-db-por-servico.md). Aluno e professor
funcionam em **todas** as plataformas (mobile e web).

## Retomar numa máquina nova (checklist Mac/Windows)
1. `git pull` — plano, agente `mvp-dev` e este brief chegam juntos.
2. Bancos: `psql -U postgres -f backend/scripts/create-dbs.sql` (idempotente);
   marcar a coluna da máquina na tabela de bancos do STATUS.md.
3. Docker Desktop instalado? `cd backend && docker compose up -d` (Redis+MinIO) e
   executar a verificação pendente das Notas de execução do P0 (no Windows o
   Docker ainda não está instalado — verificação do compose está pendente lá).
4. `cd app && flutter pub get`; `android/` vem no git (ADR-014) — as demais
   plataformas se geram com `flutter create .` **sem** `android` na lista.
   Android SDK não vem no repo: receita em [app/README.md](app/README.md)
   (instalado no Mac; pendente no Windows).
5. Segredos são locais por máquina (`.env` de cada serviço, nunca no git);
   `backend/.env.example` documenta as variáveis.
6. Continuar: dizer "implemente <próxima tarefa do docs/plan/mvp2/STATUS.md>".

## Convenções inegociáveis
- **Decisão estrutural nova → novo ADR**, nunca edição silenciosa de doc.
- **Docs curtos, normativos, densos** — "just enough, just in time"; sem prosa decorativa.
- **Design system: código é a fonte de verdade** (`app/lib/core/design_system/`), não doc.
- **i18n (ADR-011):** nenhuma string literal de UI em código (lint bloqueia); pt-BR é a
  língua-fonte; conteúdo dinâmico tem tabela de tradução com fallback pt-PT→pt-BR→en.
- **Offline (ADR-003):** offline só na **execução de treino**; eventos append-only com
  `client_id` idempotente. Ampliar escopo offline exige novo ADR.
- **Template vs execução (ADR-004):** template versionado (mutável) ≠ execução (snapshot
  imutável). Prescrição **estruturada** por set (reps, carga alvo, descanso, RPE/RIR)
  desde já — é pré-requisito do gráfico de carga do MVP 1.0.
- **Multi-tenant (ADR-001):** banco único + `tenant_id` + RLS. Conta por tenant (ADR-002).
- **Dinheiro (ADR-007):** centavos inteiros; financeiro provider-agnostic, PIX/manual primeiro.
- **Distribuição (ADR-015):** cliente valida APK/IPA por build direto; subir em loja
  é step **opcional e manual** — nunca no CI. `applicationId` só congela no 1º upload.

## Idioma e commits
Comunicação, ADRs, guidelines e mensagens de commit em **pt-BR** (doc 000 está em inglês
por legado). Commits descritivos, escopo coeso por commit.

## Comandos de dev
```bash
# Flutter
cd app && flutter pub get      # deps
flutter run -d chrome          # rodar (ou -d <device>)
flutter analyze && flutter test
dart run build_runner build   # só depois de mexer no banco local (drift, P1.7)

# Backend (por serviço, ex. identity)
cd backend && docker compose up -d          # Redis + MinIO (Postgres é o local)
psql -U postgres -f backend/scripts/create-dbs.sql   # bancos (1ª vez na máquina)
cd backend/identity && go run ./cmd/api     # subir serviço
go vet ./... && go test ./...               # verificação
```

## Manter este arquivo atualizado
Ao mudar decisão estrutural, foco de pacote ou estado do repo: registre no ADR/doc
correspondente **e** atualize os ponteiros aqui. Este é o brief que carrega entre
Windows e Mac — se ficar desatualizado, as duas máquinas divergem.
