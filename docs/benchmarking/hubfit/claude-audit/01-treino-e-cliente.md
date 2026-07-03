# Hubfit — Treino & Perfil do Cliente (auditoria Claude, 2026-07-02)

> Acesso: painel do coach em app.hubfit.com (trial). Screenshots em `./img/`.

## Navegação global (sidebar)

- **Main**: Clients, Check Ins, Tasks (com badge de pendências), Messages
- **Manage**: Packages, Community, Challenges, Teams
- **Library**: Training, Nutrition, Forms, Habits, Metrics, Resources
- **On-demand**: Resource Collections, Recipe Books, Workout Studio
- **Automations**: Autoflow, Onboarding Flow
- "Getting Started" com progressbar de onboarding do coach + "Refer & Earn"

## Lista de clientes (`/clients`)

Colunas: Client, **Tag** (In-Person / Online), **Last Check-In**, **Last Active**, **Duration ("Week 5 of 14")** — posição do cliente dentro do programa é visível na listagem. Busca, filtros, bulk select, Add Client. (img/01)

## Perfil do cliente — abas

`Overview | Check Ins | Training | Nutrition | Habits | Autoflow | Photos | Metrics | Wearable | Vault | Settings`

### Overview (img/02)
- **Client Details**: nome, email, last check-in, last active, duration (week X of Y), tags, questionnaires
- **Notes**: notas tituladas (ex.: "Goal", "Injuries") com data e flag **Private** → igual ao nosso MVP (goals/injuries), mas modelado como notas livres
- **Metrics Avg**: Weight, Body Fat, Muscle Mass, Waist com variação % (setas)
- **Activity Log**: submitted check-in, added metric, added progress photo, logged in
- **Recent Photos** (grid) e **Payments** (subscriptions + past payments) no mesmo overview
- Banner "Try the App out as this client ✨" → impersonar visão do aluno

### Training (img/03)
- Sub-abas: **Calendar | Exercise History | Completed Workouts**
- Calendário semana/mês com treinos nomeados por dia (rotação Chest & Shoulder → Back → Arms → Legs) e nº de exercícios
- Botões: **Periodise Planner** e **Import Calendar**
- Clicar num treino abre o **editor de treino inline** (mesmo editor da library) — coach edita o treino do aluno direto no calendário

### Editor de treino (img/04) — CORE
- Painel esquerdo: biblioteca de exercícios (5710), busca, list/grid, botão **New** (exercício custom)
- Treino tem **Sections** (ex.: Warmup, principal, Cool Down), cada section com instruções próprias
- Por exercício:
  - combobox para trocar o exercício + nota custom por exercício
  - **Sets** (nº) + até **4 colunas configuráveis via dropdown**: Weight, Reps, Rest, Time, (Optional) → esquema flexível por exercício
  - Reps por série em texto: `12, 12, 12^` (valores por set; sufixo aparenta indicar progressão/failure)
  - Rest como tempo `01:30`
  - Warmup/cooldown usam colunas Time (`30`s, `60`s)
- **Supersets**: exercícios agrupados visualmente em bloco
- Botões: Add Exercise, Add Section
- Save Changes desabilitado até haver mudança (dirty state)

### Exercise History (img/05) — régua pro nosso "load history"
- Lista de exercícios já executados pelo aluno (busca)
- Cards: **Max Weight, Max 1RM (estimado), Best Volume, Sessions**
- Toggle de gráfico: Weight | Reps | 1RM | Volume
- Por sessão: tabela Set × Weight × Reps × 1RM × Vol + total de volume da sessão (720 kg)

### Check Ins (img/06)
- Lista de submissions + aba "Assigned", status **Reviewed**, botão **Compare** (entre check-ins)
- Form com tipos ricos: texto, número, yes/no, slider 1–10, data, rating estrelas, **upload de fotos com "Compare"**, múltipla escolha, texto longo
- Pergunta pode ser **sincronizada com métrica** (peso "Synced" + View Graph) — resposta vira datapoint
- Coach responde com **Review** (feedback em texto, aceita links/Loom) + Submit Review

### Metrics (img/07)
- Métricas padrão (Weight kg, Body Fat %, Muscle Mass kg, Waist cm) + **New Metric** (custom, com unidade)
- Por métrica: média do período + trend %, gráfico, tabela Value × Date, Log Metric manual, range selector (Last week…)

### Wearable (img/08)
- Sub-abas: Summary, Steps, Active Calories, Sleep, Heart Rate
- Weekly Summary: Total Steps, Active kcal, Avg Sleep (hrs), Resting HR + "Guidelines"
- Ou seja: integração com wearables agregada por semana, exposta ao coach

## Library → Training

### Programs (img/09)
- Tipos de programa: **Calendar** (dias corridos, semanas) vs **Fixed** (sequência fixa) → espelha nosso dilema rotação A/B/C vs agenda (ADR-004)
- Editor: grade **Week × Day** (Day 1..28), Month 1 of 3, duplicar/apagar semana, **Add Week**
- **Periodise Planner** (img/10): modo de seleção de treinos no calendário ("Confirm 0/12") para aplicar progressão/periodização em lote
- Programa referencia treinos da library (reuso)

### Exercises (img/11)
- 5710 exercícios; colunas: Name, **Primary Focus** (músculo: Chest, Quadriceps, Biceps, Lats, Glutes, Calves, Abdominals, Lower Back, Hamstrings, Shoulders, Other), **Type** (Strength, Cardio, Stretching, Plyometrics), **Level** (Beginner/Intermediate/…), flag **Custom**
- Detalhe do exercício: Name, Instructions (texto curto), filtros = **Equipment (Barbell), Level, Muscle, Type**, Media (thumbnail/GIF + opção **Custom Video**)
- Exercícios default são read-only; custom são criados pelo coach ("New")
- Sem mapa muscular visual nem % de esforço por músculo → nosso Muscle Map segue sendo diferencial

## Ideias para o Lyfta

1. **Duration "Week X of Y" na listagem de alunos** — barato e dá contexto imediato de onde o aluno está no programa.
2. **Colunas configuráveis por exercício** (Weight/Reps/Rest/Time/RPE…) em vez de campos fixos — resolve strength + cardio + mobilidade com um único schema.
3. **Reps por série como lista** (`12, 10, 8`) — permite pirâmide sem UI pesada.
4. **Exercise History por exercício com 1RM estimado, melhor volume e gráfico** — versão mais rica do nosso "previous load visualization".
5. **Sections dentro do treino** (warmup/main/cooldown) com instruções por seção.
6. **Impersonar aluno** ("Try the App as this client") — ferramenta de suporte valiosíssima.
7. **Check-in como formulário tipado + campo sincronizado com métrica** — check-in alimenta série temporal automaticamente.
8. **Programa Calendar vs Fixed** como dois tipos explícitos de template.
