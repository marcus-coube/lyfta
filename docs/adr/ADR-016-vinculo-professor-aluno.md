# ADR-016 — Vínculo professor↔aluno: identity é o dono, checagem por M2M com cache

**Status:** Aceito
**Data:** 2026-11-07

## Contexto

ADR-008 §3 exige que o coach só veja dados de saúde dos alunos vinculados a ele.
Até a P4.6, qualquer coach do tenant acessava qualquer aluno (treino, histórico,
medidas, fotos, chat, check-ins). O vínculo é dado de organização e vive no
`identity`, mas quem serve os dados é `workout`, `assessment` e `comms`, que não
leem banco alheio (ADR-013 §2).

## Decisão

1. **Modelo:** tabela `coach_students` no `identity`, **1 coach principal por
   aluno** (`coach_id NOT NULL`). O vínculo nasce no convite do aluno (quem
   convidou) e o owner pode reatribuir. A exclusão de um coach devolve os alunos
   dele ao owner ativo mais antigo: nunca existe aluno sem professor.
2. **Owner vê todos os alunos do tenant**, sem precisar de vínculo. Coach válido é
   um usuário `active` com papel `coach` ou `owner`. Reception, quando existir,
   não acessa nenhum dado de aluno (saúde, treino, chat, check-in).
3. **Checagem:** os serviços consultam o `identity` via M2M (`X-Internal-Token`,
   ADR-013 §4/§5):
   - `GET /internal/v1/coaches/{id}/students?tenant_id=` devolve o conjunto de
     alunos do coach;
   - `GET /internal/v1/students/{id}/coach?tenant_id=` devolve o coach atual.

   A resposta fica em **cache em memória de 30 s** por (tenant, coach). O owner é
   reconhecido pela claim, sem chamada. Se o `identity` falhar, o acesso fecha
   com 500. O cliente é duplicado em cada serviço (ADR-013 §2).
4. **Contrato:** aluno não vinculado responde **404 `student_not_found`** em todo
   serviço, indistinguível de aluno inexistente ou de outro tenant.

## Consequências

- Uma reatribuição leva até 30 s para valer em todas as instâncias. Essa
  consistência eventual foi aceita.
- O `identity` vira dependência síncrona das rotas de coach. As rotas do aluno
  (`/me`, `/sync`) e o owner não dependem dele.
- O aluno continua lendo o histórico da conversa com um ex-coach. O ex-coach
  perde o acesso a ela.
- **Alternativas rejeitadas:**
  - Lista de alunos no JWT: o token fica grande e defasado até o próximo
    refresh.
  - Réplica do vínculo por evento em cada serviço: o outbox do ADR-013 §5 ainda
    não existe e o custo é alto para dev solo. É a evolução natural se a
    latência ou a carga do M2M pesarem.
- Mais de um coach por aluno (coach assistente, N:N) exige novo ADR.
