# STATUS — MVP 2.0

> Atualizado pelo agente ao concluir cada tarefa. Fonte de verdade do detalhe:
> checkboxes nos arquivos de fase.

**Próxima tarefa:** P6.5 — app: player por bloco (Flutter). **Fase P5 fechada (5/5).**

| Fase | Progresso | Situação |
|---|---|---|
| P5 — Alunos | 5/5 | fechada |
| P6 — Builder | 4/5 | em andamento |
| P7 — Financeiro | 0/5 | não iniciada |
| P8 — Dashboard e release | 0/4 | não iniciada |
| **Total** | **9/19** | |

## Bancos locais

| Banco | Criado (Windows) | Criado (Mac) |
|---|---|---|
| lyfta_billing (P7.1) | ⬜ | ⬜ |

Os quatro bancos do 1.0 seguem na tabela do [STATUS do 1.0](../mvp1/STATUS.md).

## Fora do 2.0 (decidido)

| Item | Decisão |
|---|---|
| PIX, cartão, Asaas/Stripe, webhooks | Adiado — ADR-017 §2. O schema já comporta (`provider`, `payment_provider_events`) |
| Cobrança automática, lembrete de vencimento (push/e-mail) | Adiado com o PIX |
| Pagamento parcial, multa/juros, desconto | Adiado; no 2.0 a baixa quita a fatura inteira |
| Recibo/nota fiscal | Adiado |

## Log de marcos

| Data | Evento |
|---|---|
| 2026-11-08 | Plano do 2.0 criado (18 tarefas, P5–P8); ADR-017 (serviço `billing`, só baixa manual) e ADR-018 (modelos por cópia) |
| 2026-11-08 | Revisão do usuário: acesso do coach ao financeiro vira configuração da organização; exclusão de conta bloqueada com fatura pendente e titular retido no financeiro (ADR-017 §3/§5, substitui ADR-008 §2 nesse ponto). P7.5 nova; total 19 |
| 2026-11-08 | **P5.1 concluída:** `tenants.timezone` + `coach_billing_access` (migration 0013), `GET/PUT /v1/tenant`, M2M de tenants, claim `tz` no JWT, job de pendente do comms por fuso do tenant (`NOTIFICATION_TIMEZONE` removida), seção Organização na Conta do owner |
| 2026-11-09 | **P5.2 concluída:** migration `0014_student_registry` (telefone, nascimento, status `inactive`, `user_status_events`), `/v1/students` (lista com cursor, ficha, edição, inativar/reativar, histórico), `GET/PATCH /v1/me`, M2M em lote `POST /internal/v1/students/statuses` e job de pendente do comms ignorando inativos (1 consulta por varredura); histórico inclui o aceite do convite |
| 2026-11-09 | **P5.3 concluída:** assessment `0005_student_profiles` (anamnese + lesões, RLS), `/me/profile` e `/students/{id}/profile` (aluno nunca vê `coach_notes`), `/injuries` CRUD nas duas portas, resumo do coach com objetivo e lesões ativas, exclusão física estendida; gate `health_data` em medidas, bioimpedância e anamnese (middleware), com mensagem própria do coach no app |
| 2026-11-09 | **P5.4 concluída:** app — lista de alunos paginada pelo cursor (busca, filtros de status e professor, tabela >= 840 px, header que rola), ficha `/students/:id` com abas Dados/Treino/Evolução/Check-ins (cadastro, inativar/reativar, histórico, reenviar convite), "Meus dados" na Conta do aluno; rota `/students/:id/evolution` removida |
| 2026-11-09 | **Ajustes pós-P5.4 (decisão do usuário):** `POST /v1/students/overview` no workout (último treino por `received_at` + plano ativo em lote, filtrado pelo vínculo; migration 0018) e coluna "Último treino" na lista; `POST /v1/invitations/{id}/resend` exige vínculo (404 para coach de outro aluno); diretório do chat por ids (`GET /v1/users/directory`), sem corte de 200. Master-detail no desktop fora por decisão do usuário; convite: coach só convida aluno (escalada corrigida), resend 404 `invitation_not_found`/409 `invitation_already_accepted` |
| 2026-11-09 | **P5.5 concluída — fase P5 fechada (5/5):** app — "Objetivo e saúde" na aba Dados da ficha (objetivo, experiência, meta semanal, observações médicas, notas privadas do coach, lesões com adicionar/resolver/reabrir/remover) e tela "Meu objetivo" do aluno (`/goal`, pela Conta e sugerida uma vez no primeiro acesso); lesões ativas e objetivo no Resumo da Evolução do coach; `weekly_target` passa a ser a meta do streak da Agenda (fallback: tamanho do rodízio). Sem mudança de backend; decisões: aluno vê/edita as próprias lesões e a meta semanal é só do coach (`/me` ignora `weekly_target`) |
| 2026-11-09 | **P6.1 concluída:** workout `0019_plan_templates` (modelo = plano `kind=template`, procedência `source_template_id`/`source_version_no`/`edited_after_source`), `/v1/templates` (lista com busca e cursor, criar, arquivar, atribuir em lote por cópia, destinatários, reaplicar), `save-as-template`; rotas de plano aceitam modelo (autor/owner escreve) |
| 2026-11-10 | **Ajustes na P6.1 (decisão do usuário):** `POST /v1/templates/{id}/unarchive`; `coach_id` do plano criado (assign e `POST /v1/plans`) = professor vinculado ao aluno (fallback: quem atribuiu), `coach_id` removido do corpo do `POST /plans`; existência do aluno validada no identity (M2M `students/statuses`) — `student_not_found` por item no assign; aluno inativo recebe plano |
| 2026-11-10 | **P6.2 concluída:** workout `0020_plan_version_author` (`published_by`), `POST /v1/plans/{id}/duplicate|archive`, `GET /v1/plans/{id}/versions` (autor + contagens), `POST /v1/students/{id}/plans/{plan_id}/activate` (rotação recomeça no 1º dia; arquivar o ativo = 409 `plan_is_active`) e `PUT /v1/students/{id}/plan/next-day` (override do coach, reflete no `/me/today`) |
| 2026-11-10 | **P6.3 concluída:** app — aba Modelos no shell do coach (busca, criar, arquivar/desarquivar), builder em modo modelo (título + descrição), aplicar a vários alunos com resultado por aluno, reaplicar a quem recebeu (aviso e destaque do editado), "Salvar como modelo" e aba Treino da ficha com Aplicar modelo/Duplicar/Arquivar/Ativar; plano ou modelo arquivado abre em leitura e o 409 `plan_archived` vira mensagem i18n |
| 2026-11-10 | **P6.4 concluída:** app — reordenar dias/blocos/exercícios por alça, duplicar dia e bloco, copiar série para as próximas, histórico de versões em leitura, banners de rascunho não publicado e de lesões ativas, override do próximo dia na ficha; modo leitura esconde de fato os controles de estrutura |
