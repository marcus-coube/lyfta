# P4 — Praticidade e release

Meta da fase: calendário semanal do aluno, app leve e polido, i18n completo,
roteiro de release. Fecha o MVP 1.0.

Refs normativas: ADR-011, ADR-012, doc 000 (Product Principles).

---

## - [ ] P4.1 Flutter — calendário/agenda semanal do aluno

**Objetivo:** visão semanal visual (pedido explícito do cliente).
**Passos:** aba Agenda: strip semanal (dom–sáb) + mês expansível; por dia: treino
previsto (pela rotação — próximo(s) dia(s) projetados), treino feito (sessões
sincronizadas, com resumo volume/duração ao tocar), descanso. Fonte: `GET
/v1/me/sessions?from=&to=` (adicionar no workout: sessões por período) + projeção
local da rotação. Streak simples de semanas com N treinos (contador local — 
gamificação real é 3.0).
**Aceite:** semana corrente reflete execuções reais do P1; navegação entre semanas;
teste de widget da célula de dia (3 estados).

## - [ ] P4.2 Performance e robustez ("app leve, sem travar")

**Objetivo:** metas mensuráveis, não sensação.
**Passos:**
1. Cold start ≤ 2,5 s em device Android médio (medir com `flutter run --profile`
   + timeline); adiar inits não críticos (Firebase, etc.) pós-primeiro frame.
2. Skeleton loaders nas telas de rede (Hoje, Evolução, Chat); `cached_network_image`
   com placeholders em toda mídia; listas com paginação incremental.
3. Tratamento global de erro: interceptor mapeia `code`→mensagem i18n + retry
   action; telas nunca mostram stack/erro cru; crash-safe (zona guardada + log).
4. Web: build release com `--wasm` se estável, senão canvaskit; lighthouse básico
   da tela de login; bundle inicial < 3 MB gzip (meta do doc 015 futuro).
**Aceite:** números medidos e registrados nas Notas (antes/depois); nenhum jank
visível ao rolar biblioteca com 40 GIFs.

## - [ ] P4.3 Auditoria i18n + acessibilidade básica

**Objetivo:** cumprir ADR-011 de fato e o mínimo de a11y do doc 000.
**Passos:** varrer ARBs — nenhuma chave faltando em pt-PT/en (script
`tool/check_arb_parity` que compara chaves e falha no CI); revisar plurais/gênero;
formatação de data/número/unidade via `intl` em todo lugar (grep por `toString()`
suspeitos em datas/números); a11y: labels semânticos nos botões de ícone, tamanho
de toque ≥ 48dp, contraste dos tokens do DS verificado (WCAG AA), teste com
TalkBack no fluxo de execução de treino.
**Aceite:** script de paridade ARB no CI verde; fluxo Hoje→executar→finalizar
navegável por TalkBack.

## - [ ] P4.4 E2E final + roteiro de release

**Objetivo:** MVP 1.0 validado ponta a ponta e empacotado.
**Passos:**
1. Roteiro E2E completo (`docs/plan/mvp1/e2e-final.md`): signup professor (web) →
   convida aluno (Resend real em staging) → aluno instala Android → executa treino
   offline → sync → gráfico atualiza → foto+medidas → chat com push → check-in →
   coach revisa → calendário reflete a semana. Executar também no iOS (no Mac) e
   Flutter Web como aluno.
2. Builds: Android appbundle assinado (keystore documentado fora do git), iOS
   archive (no Mac), web release; versão `1.0.0+N`; checklist de smoke por
   plataforma.
3. Varredura final: `flutter analyze` zero infos; `go vet`+testes verdes nos 4
   serviços; secrets só em env; LGPD mínima do ADR-008 presente (consentimento no
   aceite do convite + exclusão de conta — se faltou, vira tarefa antes do release).
**Aceite:** roteiro E2E 100% verde nas 3 plataformas; artefatos de build gerados;
pendências restantes listadas e classificadas (bloqueia release × vai pro 2.0).

---

## Notas de execução

(o agente anota aqui descobertas, dívidas e desvios aprovados)
