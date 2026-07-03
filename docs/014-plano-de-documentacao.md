# 014 — Plano de Documentação e Marcos

**Data:** 2026-07-02

Este plano substitui a proposta de "30–40 documentos / 300–500 páginas antes de codar".
Princípio adotado: **just enough, just in time** — a fundação é documentada a fundo
agora (errar nela custa reescrita); cada módulo é especificado na iteração em que for
implementado, quando já aprendemos com os anteriores. Documentos curtos, normativos e
sem prosa decorativa: são insumo de contexto para desenvolvimento assistido por IA,
onde densidade vale mais que volume.

## Decisões já registradas (ADRs)

| ADR | Decisão |
|---|---|
| [ADR-001](adr/ADR-001-multi-tenancy.md) | Banco único + `tenant_id` + RLS |
| [ADR-002](adr/ADR-002-identidade-conta-por-tenant.md) | Conta por tenant; e-mail único por tenant; claims JWT |
| [ADR-003](adr/ADR-003-offline-sync.md) | Offline só para execução de treino; eventos append-only |
| [ADR-004](adr/ADR-004-template-vs-execucao.md) | Template versionado ≠ execução (snapshot); blocos p/ superset |
| [ADR-005](adr/ADR-005-flutter-web.md) | Flutter Web no MVP, reavaliação com gatilho no M5 |
| [ADR-006](adr/ADR-006-monolito-modular-outbox.md) | Monolito modular Go; eventos via outbox no Postgres |
| [ADR-007](adr/ADR-007-dinheiro-financeiro.md) | Centavos inteiros; Subscription/Invoice/Payment; provider-agnostic |
| [ADR-008](adr/ADR-008-lgpd.md) | LGPD: consentimento granular e exclusão de conta no MVP |
| [ADR-009](adr/ADR-009-infra-vps.md) | VPS único + Docker Compose; backups externos obrigatórios |
| [ADR-010](adr/ADR-010-biblioteca-exercicios.md) | Base aberta + curadoria própria; biblioteca global + do tenant |
| [ADR-011](adr/ADR-011-i18n.md) | pt-BR, pt-PT, en desde o lançamento |
| [ADR-012](adr/ADR-012-escopo-mvp-packs.md) | MVP re-escopado em pacotes centrados no aluno (1.0 = loop diário) |

Novas decisões estruturais → novo ADR, nunca edição silenciosa de docs.

## Fase de fundação (escrever antes do primeiro código)

| Doc | Conteúdo | Formato |
|---|---|---|
| 002 (reescrever) | Modelo de dados completo | **SQL comentado** (migrations iniciais), não prosa |
| 003 (reescrever) | Auth + RBAC: matriz papel×permissão, claims, refresh, fluxos de convite e recuperação | Tabelas + sequência |
| 008 (reescrever) | Convenções de API: envelope de erro (`code` + params), paginação por cursor, idempotência, versionamento | ~3 páginas normativas |
| 015 (novo) | NFRs: metas de latência, tamanho de bundle web, cold start do app, disponibilidade, retenção de dados | ~2 páginas |
| 016 (novo) | Estratégia de testes + CI/CD: o que é testado onde (unit Go, integração c/ Postgres real, widget/integration Flutter), pipeline | ~2 páginas |

Docs 001/004 são absorvidos pelos ADRs (001→ADR-006/009; 004→doc de permissões, pois
plano/entitlement e feature flag são coisas distintas e serão especificados no 003).

## Marcos de implementação

> **Re-escopo (ADR-012):** o MVP deixou de ser "completo, sem cortes" e passou a ser
> entregue em pacotes centrados no aluno (doc 000). Os marcos abaixo continuam válidos
> como **unidades de implementação**, mas são reagrupados e reordenados pelos pacotes:
>
> | Pacote (doc 000) | Marcos que o compõem |
> |---|---|
> | **MVP 1.0** — loop diário do aluno | M0 + fatia mínima de M2 (builder mínimo) + M3 (execução/offline) + parte de M4 (histórico de carga) + avaliação física (subia do V1) + fatia de M5 (chat texto+imagem) |
> | **MVP 2.0** — coach monta e gerencia | M1 (alunos) + M2 completo (builder) + M6 (financeiro + dashboard) |
> | **MVP 3.0** — engajamento e análise | resto de M4 (muscle map, PRs/1RM) + resto de M5 (mídia rica) + agenda/gamificação/relatórios |

Estimativa honesta para dev solo full-time: **8–12 meses** até fechar os pacotes que
equivalem ao MVP do doc 000. Cada marco entrega algo usável de verdade; o doc de
especificação do módulo (regras de negócio + critérios de aceitação, 5–10 páginas) é
escrito **no início do marco correspondente**, não antes.

| Marco | Entrega | Docs escritos no marco |
|---|---|---|
| **M0** | Infra: repo, CI/CD, compose, esqueleto Go + Flutter, auth completo, RLS, seeds | — (coberto pela fundação) |
| **M1** | Gestão de alunos: cadastro, status, objetivos, lesões, vínculo coach, consentimento LGPD | 017-alunos |
| **M2** | Biblioteca de exercícios (import + curadoria) e workout builder (templates, versões, blocos) | 009 reescrito |
| **M3** | Execução de treino: rotação A/B/C, timer, carga anterior, offline + sync | 018-execucao-sync |
| **M4** | Histórico + muscle map: volume, progressão, mapa muscular semanal/mensal | 019-historico-musclemap |
| **M5** | Chat (texto, imagem, áudio, vídeo, PDF, recibos) + push notifications | 012 e 013 reescritos |
| **M6** | Financeiro (subscriptions, invoices, baixa manual, inadimplência) + dashboard | 011 reescrito |

M5 (chat completo com mídia e recibos) é o marco de maior risco de estouro —
se o cronograma apertar, é o candidato natural a fatiar (texto primeiro), decisão a
tomar na chegada ao marco, não agora.

V1 (avaliação física, agendamento, gamificação, relatórios, running) segue o mesmo
modelo: um doc por módulo, escrito no início do respectivo marco. O running merece
atenção especial de escopo na chegada: GPS em background + integrações de wearables é
o item individualmente mais caro do roadmap.

## O que decidimos NÃO produzir (e por quê)

- **OpenAPI escrito à mão antes do código** — vira ficção; será gerado/mantido junto
  com cada endpoint a partir do M0.
- **Wireframes em Markdown** — baixo valor; telas serão rabiscadas no Figma por marco.
- **Story mapping e backlog completos** — cerimônia de time grande; a tabela de marcos
  acima cumpre o papel para uma pessoa.
- **Design system doc de 40 páginas** — o doc 005 vira um pacote Flutter
  (`design_system/`) com tokens em código + um README curto; código é a fonte de verdade.
