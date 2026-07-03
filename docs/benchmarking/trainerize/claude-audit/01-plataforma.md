# Trainerize (ABC Trainerize) — auditoria Claude, 2026-07-02

> Acesso: painel do coach em rudsongomespereira.trainerize.com (trial 30 dias). Screenshots em `./img/`.

## Navegação global

- **Main**: Overview, Messages, Groups, Challenges, Clients, Team, Payments
- **Master Libraries**: Programs, Workouts, Exercises, Meals, Foods, Habits, Forms
- **Scheduling** e **Business** (Announcements, Client Referrals) — seções colapsáveis
- **Other**: Add-ons, Settings
- Header: **AI Workout Builder (BETA)** — gated: clicar leva à página de upgrade
- Onboarding agressivo: Intercom com bot, LIVE Q&A/masterclasses, academy, "hire an expert", referral ("next month free")

## Overview (dashboard do coach) — img/01

- **Auto-tagging de clientes por necessidade**: "We've auto-tagged your clients based on their needs... quickly follow-up with a segment in one click" — quando ninguém precisa de atenção: "Amazing work! Nobody needs your attention." 💡 conceito forte: dashboard orientado a exceção, não a listagem.
- KPIs de negócio (12 meses): Clients, Avg Client Sign-ins/Week, Avg Workouts/Week, Avg Exercise Compliance, Avg Nutrition Compliance (snapshots semanais calculados domingo à noite).
- Recent Activities com filtros (location, tipo de evento).
- Link "Set up auto messages" (mensagens automáticas em settings).

## Clients — img/02

- Estados do cliente: **Prospects | Pending | Coaching | Basic | Deactivated** — funil de aquisição embutido (prospect → cliente). Coaching = assento pago ("take up a paid seat" — pricing por nº de clientes coaching).
- Lentes da lista: **Summary | Exercise | Nutrition | Weight | Payment | Engagement** — mesma lista, colunas trocam por dimensão.
- Linha: nome, nível de acesso ("Full Access 2-way messaging"), trainer, **Main Program + fase atual ("Week 1-4") + data de término + % compliance**.
- Filtros por trainer + ADD FILTER; bulk selection; CHANGE TYPE (muda categoria do cliente em lote).

## Perfil do cliente (modal Summary) — img/03

- Abas: Summary | Consultation | Attachments | Sales | Invoices | Forms
- **Badges/gamificação** ("Recently earned badges"), Total workouts, Total cardio activities, Last signed in, Last message sent/received
- Tags manuais + **auto-tags**
- **Wearables com "Ask to Connect"**: Apple Watch, Fitbit, MyFitnessPal, Withings — coach pede a conexão, cliente aprova 💡
- **Threshold Alerts** (alertas por limiar de métrica) por cliente
- **Session Credits** (créditos de sessão/aulas avulsas)
- Dados: idade, DOB, altura, sexo, nível de atividade, timezone, **unidades por cliente (kg/km/cm)**, "Calendar look-ahead: 1 week", "Meal workflow"
- Cards: Main Program (fase + datas), Meal Plan, **Exercise Compliance por semana (2wk ago / 1wk ago / this week %)**, Nutrition Compliance, Body Weight
- Trainer's Notes com histórico

## "Switch into client" — img/04

- Botão **Open** abre NOVA ABA com a visão exata do aluno ("Your client sees the exact same thing, without editing controls") — nav própria: Dash, Calendar, Goals and Habits, Training Program, Meal Plan, Progress, Badges Earned, Classes.
- Dash do aluno: **"Things to do today"** (treino agendado + registrar peso), Virtual/In-person Classes, tiles de Progress (Steps, Sleep, Caloric Burn, Body Weight, Body Fat, Photos, Caloric Intake, Resting HR, Blood Pressure, Lean Mass), Achievements (personal bests), Recent Activities.

## Training Program — img/05, img/06, img/07

- Hierarquia: **Programa (com datas) → Training Phases ("Week 1-4", current) → Workouts** + agendamento no Calendar.
- Fase tem summary, duração em semanas, "+ Add next" (próxima fase), "Import from" (reuso da library), **Print training phase** (PDF!).
- Workout (view): tipo ("Regular workout" — há outros tipos), metadados de criação, **est. duration**, **Equipment (Body weight, Dumbbell, Mat)**, instruções, estrutura:
  - **"Superset of 3 sets"** com exercícios agrupados, "Rest for 60 sec", "Repeat new set"
  - exercício avulso: "1 set x 20, Rest 60 sec between sets"
  - painel lateral com cada exercício: vídeo (▶), instruções numeradas, **link direto pro histórico/progresso do exercício**
- **Workout Builder** (edit): nome, instruções, botões **Superset | Circuit | Duplicate | Delete | Add Rest**; sets via spinbutton; alvo por exercício = campo livre "reps, tempo, etc" com tipo **time | text** — flexível porém NÃO estruturado (não dá pra plotar carga automaticamente a partir do alvo; o tracking real acontece na execução).
- **Progression Spreadsheet**: modo alternativo de edição em planilha p/ progressões em lote entre semanas 💡.
- Ações por treino: Edit, Schedule, Progress, Copy To, Import, Duplicate, Print.

## Calendar do cliente — img/08

- Eventos: treino agendado, tarefa de registrar peso, appointments; botões Add Appointment, Schedule, "1 WEEK AHEAD".
- "Calendar look-ahead" (config por cliente) controla quanto o aluno enxerga do futuro.

## Payments — img/09

- Stripe integrado (não configurado no trial). Promessas: pagamentos globais, **bootcamps com data fixa**, assinaturas recorrentes p/ membership apps, cupons, links de produto, checkout embutido no site, **controle automático de acesso ao app conforme compra**, upsells in-app, **entrega automática de conteúdo (treino/dieta) na compra**, triggers por data de compra/início/fim de produto, Facebook Pixel.

## Pricing (img/10)

- Planos por nº de clientes: entrada **US$9/mês**, intermediário **US$23/mês**, topo ~**US$248/mês**; recursos AI e automações só nos pagos. Trial 30 dias.

## Ideias para o Lyfta

1. **Dashboard por exceção + auto-tags** ("quem precisa de atenção hoje") em vez de só listas — encaixa no nosso Dashboard MVP (ativos/inadimplentes/treinos de hoje).
2. **Funil Prospect → Pending → Coaching** — CRM leve embutido; nosso cadastro de aluno pode nascer com estados.
3. **Lentes na lista de alunos** (treino/financeiro/engajamento) sem sair da lista.
4. **Fases de programa com datas + "Add next" + import** — periodização em blocos, bate com nosso ADR-004 (template vs execução).
5. **Switch into client em nova aba** — visão espelho do aluno (Hubfit tem o equivalente).
6. **Compliance semanal (%)** como métrica de 1ª classe por aluno e agregada no dashboard do coach.
7. **Threshold alerts por métrica** — rule-based, sem IA, viável no MVP/V1.
8. **Print/PDF de treino e fase** — personal brasileiro adora entregar PDF; barato e diferencial prático.
9. **Equipment por treino** derivado dos exercícios — filtro "treino em casa".
10. **Ask to Connect (wearables)** — a permissão de dados parte do coach e o aluno aprova.
