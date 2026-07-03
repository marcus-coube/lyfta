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
- `backend/` — microserviços Go: `identity` (8081) · `workout` (8082) ·
  `assessment` (8083) · `comms` (8084). Stack pinada, portas e bancos em
  [backend/README.md](backend/README.md). Futuro: cada serviço em repo próprio —
  **nunca** importar código entre serviços.
- `docs/` — documentação. **Fonte de verdade de produto e arquitetura.**
- `.claude/agents/mvp-dev.md` — agente (Sonnet) que executa o plano do MVP, uma
  tarefa por invocação.

## Onde está a verdade (ler antes de propor mudanças)
- **[docs/000-product_description.md](docs/000-product_description.md)** — roadmap em
  **pacotes** (MVP 1.0 → 2.0 → 3.0 → 4.0 running → V2 IA → Futuro).
- **[docs/014-plano-de-documentacao.md](docs/014-plano-de-documentacao.md)** — plano de
  docs + marcos de implementação e de-para marco→pacote.
- **[docs/adr/](docs/adr/)** — decisões estruturais (ADR-001..013). São normativas.
- **[docs/plan/mvp1/](docs/plan/mvp1/)** — plano de execução do MVP 1.0 (P0–P4,
  29 tarefas, protocolo do agente). Progresso em `STATUS.md`.
- **[docs/benchmarking/](docs/benchmarking/)** — auditoria HubFit × Trainerize × Lyfta.
- `docs/guidelines/` — convenções de código (ex.: `flutter.md`).

## Estado atual (2026-07-03)
Bootstrap Flutter (DS + login visual) + **plano de execução do MVP 1.0 pronto**
([docs/plan/mvp1/](docs/plan/mvp1/)). Backend ainda não implementado (começa em P0).
**Foco: executar o plano na ordem P0→P4** via agente `mvp-dev` (uma tarefa por vez).
Escopo do MVP em [ADR-012](docs/adr/ADR-012-escopo-mvp-packs.md); arquitetura de
serviços em [ADR-013](docs/adr/ADR-013-microservicos-db-por-servico.md).
Aluno e professor funcionam em **todas** as plataformas (mobile e web).

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

## Idioma e commits
Comunicação, ADRs, guidelines e mensagens de commit em **pt-BR** (doc 000 está em inglês
por legado). Commits descritivos, escopo coeso por commit.

## Comandos de dev
```bash
# Flutter
cd app && flutter pub get      # deps
flutter run -d chrome          # rodar (ou -d <device>)
flutter analyze && flutter test

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
