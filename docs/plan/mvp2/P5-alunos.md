# P5 — Gestão de alunos

Meta da fase: o coach cadastra, acompanha e inativa alunos com uma ficha
completa (dados, objetivo, lesões, treino, evolução, check-ins), e o tenant
ganha fuso próprio — pré-requisito dos jobs do financeiro (P7).

Refs normativas: ADR-001, ADR-002, ADR-007 §3, ADR-008, ADR-013, ADR-016.

---

## - [ ] P5.1 Fuso e configurações do tenant (identity, comms, workout)

**Objetivo:** `tenants.timezone` (ADR-007 §3) e quitar a dívida do
`NOTIFICATION_TIMEZONE` único da P3.4.
**Passos:**
1. identity: migration com `tenants.timezone TEXT NOT NULL DEFAULT
   'America/Sao_Paulo'` (validar nome IANA com `time.LoadLocation`).
   Mais `tenants.coach_billing_access TEXT NOT NULL DEFAULT 'status_only'
   CHECK (IN ('status_only','own_students'))` (ADR-017 §3; o financeiro só usa
   na P7, mas a configuração nasce aqui com as outras do tenant).
   `GET /v1/tenant` (todo papel: nome, slug, locale, timezone,
   `coach_billing_access`) e `PUT /v1/tenant` (owner). JWT ganha a claim `tz`.
2. identity M2M: `GET /internal/v1/tenants?after=&limit=` (id + timezone,
   cursor) para jobs que varrem todos os tenants, e `GET /internal/v1/tenants/{id}`
   (timezone + `coach_billing_access`).
3. comms: o job de treino pendente varre por tenant no fuso de cada um (lista
   por M2M, cache de 10 min), mantendo o mecanismo da P3.4 — só a janela
   `[since, until)` passa a ser por tenant. `NOTIFICATION_TIMEZONE` sai.
4. workout: "hoje" do aluno (`/me/today`, `/me/sessions`) não muda de regra,
   mas onde o servidor precisar de dia civil usa a claim `tz`.
5. App: seção "Organização" na tela Conta do owner (nome, fuso com busca na
   lista IANA mais comum do BR/PT + "outro"). O toggle do financeiro entra na
   P7.4, junto da tela que ele controla.
**Aceite:** dois tenants com fusos diferentes recebem o push de pendente no
horário local de cada um (teste do job com relógio fake); `PUT /v1/tenant` com
fuso inválido = 422 `invalid_timezone`; teste de widget da seção Organização.

## - [ ] P5.2 Cadastro e status do aluno (identity)

**Objetivo:** dados cadastrais e ciclo de vida do aluno sem apagar nada.
**Passos:**
1. Migration: `users.phone TEXT`, `users.birth_date DATE` (opcionais).
   Status do aluno: `active` ↔ `inactive` (novo valor no CHECK; `disabled`
   segue para bloqueio administrativo). Inativo **não loga** (refresh tokens
   revogados), some da lista padrão e mantém todos os dados; reativar devolve o
   acesso. Tabela `user_status_events` (append-only: de, para, por quem,
   quando, motivo opcional) para o histórico.
2. `GET /v1/students` (substitui o uso de `/v1/users?role=student` no app):
   filtros `status`, `coach_id` (owner), busca por nome/e-mail, ordenação por
   nome, **cursor sem teto de 200** (quita a dívida da P3.5/P4.4).
   `GET /v1/students/{id}` (cadastro + coach + status + convite pendente).
3. `PATCH /v1/students/{id}` (nome, telefone, nascimento) e
   `POST /v1/students/{id}/deactivate|reactivate` — coach vinculado ou owner
   (ADR-016). `GET /v1/students/{id}/status-history`.
4. O aluno edita o próprio telefone/nascimento em `PATCH /v1/me`.
5. Serviços que varrem alunos (job de pendente no comms) ignoram inativos:
   `GET /internal/v1/students/{id}` passa a devolver `status`, e o
   `coachlink` continua valendo para inativos (o coach ainda abre a ficha).
**Aceite:** inativar bloqueia login e refresh do aluno e o tira do push de
pendente; reativar devolve; coach de outro aluno = 404; histórico registra as
duas transições; teste de handler (feliz + 404 + aluno já inativo = 409
`already_inactive`).

## - [ ] P5.3 Anamnese: objetivo, lesões e restrições (assessment)

**Objetivo:** o coach prescreve sabendo do que o aluno tem — dado de saúde,
por isso no `assessment` (ADR-008 §1, apagado na exclusão).
**Passos:**
1. Migrations: `student_profiles` (1 por aluno: `goal` código estável
   `hypertrophy|weight_loss|strength|conditioning|health|rehab|other`,
   `goal_notes`, `training_experience` `beginner|intermediate|advanced`,
   `weekly_target` 1–7, `medical_notes`, `coach_notes` — esta só o coach lê,
   `updated_at`, `updated_by`) e `student_injuries` (região corporal código
   estável, descrição, `since`, `resolved_at`, `created_by`). RLS + índice
   `(tenant_id, student_id, ...)`.
2. Portas `/me/profile` (aluno lê/edita objetivo, experiência e
   `medical_notes`; nunca vê `coach_notes`) e `/students/{id}/profile` (coach
   vinculado/owner), `GET/POST/PATCH/DELETE .../injuries`. Gate da claim
   `health_data` igual às medidas.
3. `GET /v1/students/{id}/summary` (P2.3) ganha objetivo e lesões ativas.
4. `DELETE /internal/v1/users/{id}` apaga as duas tabelas (exclusão física).
**Aceite:** aluno não lê `coach_notes` (teste); lesão resolvida sai do resumo
de ativas; exclusão de conta apaga perfil e lesões; teste de isolamento
cross-tenant nos repositórios novos.

## - [ ] P5.4 App — lista de alunos e cadastro (Flutter)

**Objetivo:** a lista de alunos vira ferramenta de gestão.
**Passos:**
1. `features/students/`: lista com busca, filtro por status (ativos padrão,
   inativos, convites pendentes) e por professor (owner); paginação
   incremental pelo cursor da P5.2; acima de 840 px vira tabela (nome,
   professor, último treino, status) — corrige também o header que estoura em
   janela baixa (dívida do P1.8).
2. Ficha do aluno (`/students/:id`) com abas: **Dados** (cadastro editável,
   status com inativar/reativar e confirmação, histórico de status, trocar
   professor — owner, já existente), **Treino** (planos, P6), **Evolução**
   (existente, `EvolutionScope.student`), **Check-ins** (existente). Master-detail
   no desktop.
3. Aluno: telefone e nascimento na tela Conta.
**Aceite:** coach com 250 alunos de seed rola a lista sem teto; inativar
reflete na lista e no login do aluno; teste de widget da lista (filtro +
estado vazio) e da aba Dados. Strings nos 3 idiomas.

## - [ ] P5.5 App — anamnese na ficha e no perfil do aluno (Flutter)

**Objetivo:** objetivo e lesões visíveis onde o coach decide.
**Passos:**
1. Aba Dados ganha "Objetivo e saúde": objetivo, experiência, meta semanal,
   observações médicas, notas privadas do coach, lesões (adicionar, resolver,
   remover). Regiões e objetivos traduzidos no app (códigos estáveis, ADR-011 §5).
2. Aluno: tela "Meu objetivo" (objetivo, experiência, observações médicas)
   acessível pela Conta e sugerida uma vez após o primeiro login.
3. `weekly_target` substitui a meta local do streak da Agenda (P4.1), com
   fallback para o tamanho do rodízio quando vazio.
**Aceite:** lesão ativa aparece no Resumo da Evolução do coach; aluno edita o
objetivo e o coach vê; teste de widget do formulário de lesão.

---

## Notas de execução

(o agente anota aqui descobertas, dívidas e desvios aprovados)
