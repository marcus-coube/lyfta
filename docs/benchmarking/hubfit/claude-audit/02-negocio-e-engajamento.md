# Hubfit — Financeiro, Automações & Engajamento (auditoria Claude, 2026-07-02)

## Packages (financeiro) — img/12

- Monetização é 100% **Stripe Connect**: sem Stripe conectado, não recebe (banner "Connect to Stripe"), mas dá pra criar pacotes antes.
- Lista: Package, Price, Duration ("Monthly x 1"), toggles **Active** e **Visible**.
- Extras: **Coupons** (aba própria) e **Packages Page** — página pública de venda/checkout gerada pela plataforma.
- Wizard de pacote em 3 passos:
  1. **Setup**: nome, descrição, moeda, tipo de plano (Monthly/…), duração ("for how long? 1 Month"), preço, **free trial** (3 days…), **initial fee** (taxa de matrícula), "instant access upon purchase", preview do payout total.
  2. **Automations**: seleciona um **Onboarding Flow** disparado na compra.
  3. **Benefits**: bullets que aparecem na pricing page.
- No perfil do cliente: card Payments com "All Subscriptions" + "Past Payments".
- ≠ Lyfta: nosso MVP é conciliação manual de mensalidade (Brasil/PIX); Hubfit não tem controle manual de inadimplência visível — tudo via assinatura Stripe. **O modelo deles não cobre o caso "personal cobra por fora e só registra"** — que é justamente nosso nicho inicial.

## Automations

- **Autoflow** (img/13): bloqueado no trial (plano Ultimate). Descrição: sequência de eventos automatizados para entregar programas de 3/6/9 meses — e-mails, mensagens, notas, notificações in-app agendadas.
- **Onboarding Flow**: flows nomeados criados à parte e vinculados a pacotes (disparo na compra). Criação = só nome, depois abre editor (não explorado — evitei criar dados na conta).

## Forms (img/15)

- Dois tipos: **Check-Ins** (recorrentes, com Schedule: Daily/Weekly...) e **Questionnaires** (intake/anamnese, aparecem no perfil do cliente).
- Builder: lista de perguntas com Type e Required, botões Schedule / Reposition / Add Question.
- Pergunta pode ser **vinculada a uma métrica** (ex.: "Today's hydration (liters)" → metric Water (L)) — resposta alimenta a série temporal automaticamente. 💡 ótima ideia.

## Habits (img/14)

- Hábito = emoji + nome + goal quantificado ("Complete 10000 steps every day", "8 cups every day") + dias da semana + horário do lembrete.
- Library global → atribuível por cliente (aba Habits no perfil).

## On-demand

- **Workout Studio**: coleções de treinos self-service ("Gym Workouts", "Home Workouts") atribuíveis a N clientes — treino sem prescrição individual.
- **Resource Collections** e **Recipe Books**: conteúdo/PDF/vídeo empacotado para clientes.

## Engajamento / Comunidade (não explorado a fundo)

- **Community** (feed), **Challenges** (marcado "New"), **Teams** (grupos de clientes), **Tasks** (to-dos do coach com badge), **Messages** (chat).

## Onboarding do coach (img — getting-started)

- Checklist de ativação "1/5 completed" com progressbar na sidebar: Create account → Install app → **Review a check-in** → **Automate client onboarding** → **Assign a program**.
- Demo video + Academy + Help articles na mesma página; toda página do app tem link "Learn more" contextual para o help center.
- 💡 Activation checklist orientada aos "aha moments" do produto — vale copiar no Lyfta (tenant novo: cadastrar aluno → montar treino → atribuir → primeiro treino executado).

## Observações gerais de UX

- Sidebar com agrupamento claro (Main/Manage/Library/Automations) — library global vs dados do cliente bem separados: **tudo que é library é template reutilizável; a atribuição acontece no contexto do cliente**.
- "Try the App out as this client ✨" (impersonation) disponível direto no perfil.
- Copy sempre orientada a ação + "Learn more" por página.
- Web do coach é desktop-first; app mobile é para coach e cliente (banners de install).
