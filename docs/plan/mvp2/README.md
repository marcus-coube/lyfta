# Plano de execução — MVP 2.0

Pacote 2.0 do [doc 000](../../000-product_description.md): **o coach monta e
gerencia** — gestão de alunos, builder completo, financeiro e dashboard. Mesmo
modo de execução do [MVP 1.0](../mvp1/README.md): **uma tarefa por vez** pelo
agente `mvp-dev`, com supervisão humana. A numeração continua a do 1.0 (P5 em
diante), então "implemente P5.1" não colide com nenhuma tarefa antiga.

## Escopo

| Entra | Fica fora (pacote seguinte ou sem data) |
|---|---|
| Ficha do aluno: cadastro, status ativo/inativo, objetivo, lesões | Agenda do coach, sessões de avaliação (3.0) |
| Fuso por tenant (pré-requisito dos jobs do financeiro) | Coach assistente / N:N (ADR-016) |
| Modelos de treino aplicados por cópia (ADR-018), duplicar, reordenar, versões, override do dia pelo coach | Progressão automática de carga, 1RM estimado (3.0) |
| Player que respeita bloco (superset, circuito) | Muscle map (3.0) |
| Financeiro com **baixa manual** (ADR-017) | **PIX**, cartão, Asaas/Stripe, cobrança automática, lembrete de vencimento, parcial, multa/juros, recibo/NF |
| Dashboard do coach e do owner | Relatórios exportáveis (3.0) |

Pendências de loja (L1–L10 do [STATUS do 1.0](../mvp1/STATUS.md)) seguem fora do
plano: são ações humanas, não tarefas do agente.

## Fases

| Fase | Arquivo | Entrega |
|---|---|---|
| P5 | [P5-alunos.md](P5-alunos.md) | Fuso por tenant, cadastro e status do aluno, anamnese, ficha do aluno no app |
| P6 | [P6-builder.md](P6-builder.md) | Modelos, gestão de planos, ergonomia do builder, player por bloco |
| P7 | [P7-financeiro.md](P7-financeiro.md) | Serviço `billing`: planos, assinaturas, faturas, baixa manual, jobs, exclusão de conta com fatura pendente |
| P8 | [P8-dashboard.md](P8-dashboard.md) | Dashboard, dívidas do 1.0 que o 2.0 encosta, E2E e release 2.0.0 |

Ordem P5→P8. P6 não depende de P5 (pode ser adiantada); P7 depende da P5.1
(fuso) e da P5.2 (status do aluno); P8 depende de todas.

Progresso agregado: [STATUS.md](STATUS.md). Fonte de verdade do progresso: os
checkboxes nos arquivos de fase.

## Protocolo do agente

O mesmo do [README do 1.0](../mvp1/README.md#protocolo-do-agente-obrigatório),
trocando os caminhos: ler este README e o arquivo da fase; registrar em
`docs/plan/mvp2/STATUS.md`; commit `feat(p5.1): ...`. Sem ID explícito, pegar a
primeira tarefa não marcada na ordem P5→P8.

## Regras transversais (além das do 1.0)

Todas as regras transversais do 1.0 continuam valendo (i18n, RLS, offline só na
execução, prescrição estruturada, ambos os papéis em todas as plataformas,
testes mínimos). Mais:

- **Dinheiro (ADR-007):** `amount_cents BIGINT` + `currency` em toda camada. No
  Flutter, valor é `int` de centavos; formatação só com `NumberFormat.currency`
  do `intl` no locale da tela. Proibido `double` para dinheiro, inclusive em
  campo de formulário (parse de texto direto para centavos).
- **Fuso (ADR-007 §3):** "hoje", "mês corrente" e vencimento são calculados no
  `tenants.timezone`, nunca no relógio do servidor nem em UTC puro.
- **Vínculo (ADR-016):** toda rota nova de coach sobre aluno passa pelo
  `coachlink` (404 `student_not_found` fora do vínculo). Owner vê todos.
- **Acesso ao financeiro (ADR-017 §3):** owner vê tudo; o coach depende de
  `tenants.coach_billing_access` (`status_only` = só o selo de inadimplente;
  `own_students` = assinaturas, faturas e baixa dos alunos dele). Estorno,
  planos e receita são sempre só do owner. Aluno lê as próprias faturas.
- **Desktop-first na web do coach:** telas de gestão (lista de alunos, builder,
  financeiro, dashboard) usam o espaço acima de 840 px (tabela/grid, master-detail);
  abaixo disso, coluna única.
