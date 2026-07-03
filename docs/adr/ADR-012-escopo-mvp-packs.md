# ADR-012 — Re-escopo do MVP em pacotes centrados no aluno

**Status:** Aceito
**Data:** 2026-07-03

## Contexto

O doc 000 e o [doc 014](../014-plano-de-documentacao.md) haviam fechado o MVP como
"completo, sem cortes" (marcos M0–M6: alunos, builder, execução, muscle map, chat,
financeiro, dashboard). O cliente revisou a prioridade e definiu um MVP **centrado na
experiência do aluno**: treinar o dia, evoluir (carga, fotos, medidas) e falar com o
personal, funcionando offline. Isso reordena o escopo — puxa a **avaliação física**
(estava no V1) para o primeiro pacote e tira do primeiro pacote **muscle map,
financeiro, dashboard e a profundidade de gestão do coach**. É uma reversão da decisão
de escopo anterior e, por isso, um novo ADR em vez de edição silenciosa.

## Decisão

1. **O MVP passa a ser entregue em pacotes numerados (MVP 1.0, 2.0, 3.0…)**, priorizados
   pela lista do cliente. A estrutura canônica vive no doc 000; este ADR registra o
   *porquê* da reordenação.

2. **MVP 1.0 = o loop diário do aluno.** Escopo fechado:
   - Execução de treino (tela do dia, vídeo/GIF, registro de carga/série/rep, timer de
     descanso com som/vibração) — já coberto por [ADR-003](ADR-003-offline-sync.md) e
     [ADR-004](ADR-004-template-vs-execucao.md).
   - Histórico de carga por exercício (gráfico de progressão).
   - Avaliação física **digitada manualmente**: fotos antes/depois, medidas corporais,
     bioimpedância. Integração com balança/wearable fica fora (3.0+).
   - Chat aluno↔coach **texto + imagem** apenas; avaliação do treino (check-in tipado:
     feedback/dificuldade/dor); push de treino pendente e nova mensagem.
   - Offline (escopo do ADR-003), login simples + recuperação, calendário semanal do aluno.

3. **Enablers obrigatórios do 1.0 que o cliente não listou** (sem eles não há "treino do
   dia"): auth sobre a base multi-tenant, **builder mínimo do coach** + biblioteca de
   exercícios com mídia, e a infra de backend/sync (o antigo M0). O builder completo
   (versões, blocos superset/circuit, rotação automática) fica no MVP 2.0.

4. **Prescrição estruturada é pré-requisito do 1.0, não do 2.0.** Mesmo com builder
   mínimo, `prescribed_sets` nasce estruturado (reps, carga alvo, descanso, RPE/RIR —
   ADR-004). Sem isso o gráfico de carga do 1.0 não existe. Confirma a recomendação #1
   do benchmarking ("impacta o modelo de dados JÁ").

5. **Muscle map permanece no MVP 3.0**, apesar de ser o diferencial que HubFit e
   Trainerize não têm (síntese de benchmarking). Decisão consciente do cliente:
   experiência do aluno primeiro; o diferencial de análise vem depois do core.

6. **Demais pacotes** (resumo; detalhe no doc 000):
   - **2.0** — builder completo, gestão de alunos, financeiro (PIX/manual), dashboard.
   - **3.0** — muscle map, histórico avançado (PRs/1RM), chat com mídia rica, agenda do
     coach, gamificação, hábitos, relatórios, notificações ampliadas.
   - **4.0** — módulo running (vertical completa).
   - **V2** — camada de IA (já postergada).
   - **Futuro** — wearables, live sync, QR/NFC, marketplace, perfis públicos, white-label.

## Consequências

- Os marcos M0–M6 do doc 014 continuam válidos como unidades de implementação; mudam de
  agrupamento e ordem de entrega. O doc 014 passa a apontar para os pacotes do doc 000.
- O 1.0 fica maior do que a lista sugere: os enablers (auth + builder mínimo + sync) são
  vários meses de dev solo antes da primeira tela útil ao aluno. Honestidade de prazo
  mantida: o 1.0 não é "um app de treino" isolado, é a fatia vertical mínima ponta a ponta.
- Financeiro sai do primeiro pacote: a plataforma não monetiza o coach no 1.0. Aceito
  porque a validação buscada é de engajamento do aluno, não de cobrança.
- Ampliar o offline além da execução (ex.: chat offline) continua exigindo novo ADR
  (regra do ADR-003) — não muda aqui.
