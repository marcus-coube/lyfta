# Síntese comparativa — Hubfit × Trainerize × Lyfta

> Auditoria feita por Claude via Playwright em 2026-07-02, contas trial de coach.
> Notas detalhadas: `hubfit/claude-audit/` e `trainerize/claude-audit/` (screenshots em `img/`).

## Posicionamento

| | Hubfit | Trainerize (ABC) | Lyfta (nós) |
|---|---|---|---|
| Público | Coach online (1:N remoto) | Personal/estúdio, forte em negócio & escala | Academias + personais + estúdios BR, multi-tenant |
| Monetização do coach | Stripe subscriptions + packages page | Stripe + bootcamps/upsells/checkout embutido | **Conciliação manual / PIX primeiro**, gateway depois |
| Cobrança da plataforma | Por plano (Autoflow = Ultimate) | Por nº de clientes "Coaching" (US$9→248) | A definir (assento/aluno?) |
| IA | Não visível no trial | AI Workout Builder (BETA, pago) | Adiada para V2 (decisão já tomada) |

## Modelo de treino (o core pra gente)

| Conceito | Hubfit | Trainerize | Lição p/ Lyfta |
|---|---|---|---|
| Hierarquia | Program (Calendar ou Fixed) → Week×Day → Workout → Sections → Exercises | Program (datado) → Phases (Week 1-4) → Workouts + Calendar | Suportar **blocos/fases** e os dois modos de entrega (agenda vs sequência fixa) — já é a direção do ADR-004 |
| Prescrição | **4 colunas configuráveis** por exercício (Weight/Reps/Rest/Time/…), reps por série "12, 12, 12^" | Alvo em **texto livre** ("reps, tempo, etc" — time ou text) | Hubfit >> Trainerize aqui. Prescrição estruturada permite gráfico de carga, PRs e pré-preenchimento na execução. Copiar Hubfit. |
| Agrupamento | Sections (Warmup/Main/Cooldown) + supersets | Supersets + **Circuits** + Rest blocks | Modelar section/bloco com tipo (normal/superset/circuit) e rest explícito |
| Periodização | **Periodise Planner** (seleção em lote no calendário) | **Progression Spreadsheet** (planilha de progressões) | Ambos atacam o mesmo job: editar progressão de N semanas de uma vez. Matador de tempo do coach — vale protótipo cedo (pós-MVP) |
| Histórico | Por exercício: Max Weight, **1RM estimado**, Best Volume, Sessions + gráficos W/R/1RM/Vol + tabela por sessão | Link p/ progresso por exercício a partir do treino | Nosso "previous load" do MVP deve virar isso: página por exercício com PRs + gráfico |
| Biblioteca | 5710 exercícios (Primary Focus/Type/Level/Equipment, GIF, custom read-write) | Biblioteca própria + custom + vídeos | Bate com ADR-010; ter Equipment como atributo (filtro "treino em casa") |
| Execução | (app mobile, não auditado) | (app mobile, não auditado) | Auditar apps mobile numa próxima sessão — nosso diferencial de execução offline continua sem concorrente visível |
| Muscle map | ❌ não tem | ❌ não tem | **Nosso diferencial do MVP se mantém** |

## Acompanhamento do aluno

- **Check-ins (Hubfit é referência)**: formulário tipado (texto/número/escala/data/estrelas/foto/múltipla escolha) + **pergunta sincronizada com métrica** + fluxo de review do coach + Compare de fotos. Trainerize tem Forms mais simples.
- **Métricas**: ambos têm métricas custom com unidade, log manual + sync de wearable, gráfico + tabela. Trainerize soma **Threshold Alerts** (alerta por limiar) e compliance semanal como % de 1ª classe.
- **Wearables**: Hubfit agrega semana (Steps/kcal/Sleep/HR) na aba do cliente; Trainerize integra Apple Watch/Fitbit/MyFitnessPal/Withings com fluxo "Ask to Connect". Para nós é V1+ (Health Connect/HealthKit já previstos no módulo running).
- **Gamificação**: Trainerize tem badges/achievements/personal bests nativos (nosso V1 prevê streaks/achievements — validado).
- **Hábitos**: ambos têm habits com meta quantificada + dias/horário. Barato e engaja; candidato a subir na prioridade.

## Negócio do coach

- Ambos: funil/CRM leve (Trainerize: Prospects→Pending→Coaching), packages com trial/matrícula, checkout público, cupons, automação pós-compra (onboarding flow / entrega de conteúdo), grupos/challenges/comunidade, mensagens com auto-messages.
- **Nenhum dos dois cobre bem o fluxo brasileiro** de mensalidade manual/PIX/inadimplência que é o nosso MVP financeiro — confirmação de nicho.
- Dashboards: Trainerize é orientado a exceção (auto-tags "precisa de atenção") + KPIs de negócio; Hubfit é mais operacional (tasks, check-ins pendentes).

## UX / Growth (padrões que valem copiar)

1. Activation checklist com progresso na sidebar (Hubfit "Getting Started 1/5"; Trainerize com masterclasses+Intercom).
2. "Learn more" contextual em toda página → help center.
3. Impersonation do aluno em 1 clique (ambos).
4. Library global (templates) separada do contexto do cliente (instâncias) — mesma separação template/execução do nosso ADR-004.
5. Estado vazio sempre com CTA ("Create your first...").
6. Features premium visíveis mas bloqueadas (Autoflow/AI) — upsell dentro do produto; casa com nossa arquitetura de feature flags.

## Top 10 recomendações acionáveis para o Lyfta

1. Prescrição estruturada por exercício com colunas configuráveis (Weight/Reps/Rest/Time/RPE) e reps por série — modelo Hubfit (impacta modelo de dados do workout engine JÁ).
2. Página de histórico por exercício: PRs (max weight, 1RM estimado, best volume), gráfico e tabela por sessão.
3. Sections tipadas no treino (warmup/main/cooldown; normal/superset/circuit) com rest explícito.
4. Programa com fases datadas + tipo Calendar/Fixed (rotação A/B/C = caso do Fixed).
5. "Week X of Y" do aluno visível na listagem + % compliance semanal.
6. Dashboard por exceção com auto-tags rule-based (sem treino há N dias, check-in atrasado, pagamento vencido).
7. Check-in tipado com pergunta ligada a métrica + review do coach (nosso chat já previsto vira o canal do feedback).
8. Impersonar aluno (suporte e confiança do coach).
9. Print/PDF de treino/fase (hábito forte no mercado BR).
10. Activation checklist no onboarding do tenant.

## O que decidimos NÃO copiar (por ora)

- Stripe-first / checkout público — nosso financeiro MVP é manual (PIX/dinheiro), gateway vem depois.
- Nutrition completo (meal plans/foods/recipes) — fora de escopo declarado.
- Comunidade/challenges/teams — V1+, engajamento vem depois do core.
- IA (AI Workout Builder) — já postergado para V2 por decisão de produto.
- Marketplace de "hire an expert", add-ons pagos — não faz sentido no nosso estágio.

## Pendências de benchmark (próximas sessões)

- Apps mobile (aluno) de ambos — execução de treino, rest timer, offline.
- Autoflow do Hubfit e AI Builder do Trainerize exigem plano pago.
- Scheduling/appointments do Trainerize (não aprofundado).
- Editor de Onboarding Flow do Hubfit (não criei dados na conta — exploração somente leitura).
