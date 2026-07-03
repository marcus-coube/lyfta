# Plano de execução — MVP 1.0

Plano passo a passo do MVP 1.0 ([ADR-012](../../adr/ADR-012-escopo-mvp-packs.md)),
escrito para ser executado **uma tarefa por vez** pelo agente `mvp-dev`
(`.claude/agents/mvp-dev.md`, modelo Sonnet) com supervisão humana.

## Fases

| Fase | Arquivo | Entrega |
|---|---|---|
| P0 | [P0-fundacao.md](P0-fundacao.md) | Infra local, identity (auth+convites Resend), Flutter conectado |
| P1 | [P1-treino.md](P1-treino.md) | Coach monta treino → aluno executa offline com timer e sync |
| P2 | [P2-evolucao.md](P2-evolucao.md) | Gráfico de carga, fotos, medidas, bioimpedância |
| P3 | [P3-comunicacao.md](P3-comunicacao.md) | Chat, avaliação de treino, push |
| P4 | [P4-praticidade.md](P4-praticidade.md) | Calendário semanal, performance, i18n, release |

Progresso agregado: [STATUS.md](STATUS.md). Fonte de verdade do progresso: os
checkboxes dentro de cada arquivo de fase.

## Protocolo do agente (obrigatório)

1. **Ler antes de codar:** `CLAUDE.md`, `backend/README.md`, o arquivo da fase da
   tarefa e os ADRs citados nela. Nunca contrariar ADR — em conflito, **parar e
   reportar**, não improvisar.
2. **Uma tarefa por invocação** (ex.: "implemente P1.4"). Sem ID explícito, pegar a
   primeira tarefa não marcada na ordem P0→P4.
3. **Implementar somente o escopo da tarefa.** Descobriu algo faltando? Anotar na
   seção "Notas de execução" do arquivo da fase — não expandir o escopo.
4. **Verificar:** backend `go vet ./... && go test ./...` no serviço tocado;
   Flutter `flutter analyze && flutter test`. Tarefa com critério de aceite manual:
   descrever no commit como verificar.
5. **Registrar:** marcar `[x]` no checkbox da tarefa, atualizar `STATUS.md`
   (contador + "próxima tarefa"), commit em pt-BR no formato
   `feat(p1.4): atribuição de plano ao aluno` (ou `fix|chore|test`). Um commit por
   tarefa, escopo coeso. Não fazer push (o humano faz).
6. **Dependências:** usar apenas as pinadas em `backend/README.md` e nas tarefas.
   Precisa de outra? Parar e justificar antes.

## Regras transversais (valem para toda tarefa)

- **i18n (ADR-011):** nenhuma string literal de UI; toda tela nasce com chaves ARB
  pt-BR (fonte), pt-PT e en.
- **Multi-tenant (ADR-001):** toda tabela nova tem `tenant_id` + policy RLS + índice
  começando por `tenant_id`.
- **Offline (ADR-003):** só a execução de treino é offline. Nada mais.
- **Prescrição estruturada (ADR-004/012):** `prescribed_sets` sempre estruturado.
- **Ambos os papéis em todas as plataformas:** aluno e professor funcionam em
  Android, iOS e Web — sem gating por plataforma; layouts responsivos.
- **Testes mínimos por tarefa:** backend = teste de handler/repo do fluxo feliz + 1
  caso de erro; Flutter = teste de widget da tela nova quando indicado na tarefa.
