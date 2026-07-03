# ADR-013 — Backend em microserviços com banco por serviço

**Status:** Aceito (supersede [ADR-006](ADR-006-monolito-modular-outbox.md))
**Data:** 2026-07-03

## Contexto

O ADR-006 fixava monolito modular Go com outbox. Decisão do fundador (2026-07-03):
backend em **microserviços, projetos separados, cada um com seu próprio PostgreSQL**,
para permitir a separação futura em repositórios independentes. Por ora tudo vive em
`backend/` neste repositório (melhor contexto para desenvolvimento assistido por IA).

## Decisão

1. **4 serviços coarse-grained no MVP 1.0** — granularidade mínima viável para dev
   solo; fatiar mais fino exige novo ADR:

   | Serviço | Responsabilidade | Banco | Porta dev |
   |---|---|---|---|
   | `identity` | Tenants, usuários, papéis, auth JWT, convites (Resend), recuperação de senha | `lyfta_identity` | 8081 |
   | `workout` | Biblioteca de exercícios, templates/prescrição (ADR-004), execução/logs, sync offline (ADR-003), mídia de exercício | `lyfta_workout` | 8082 |
   | `assessment` | Medidas corporais, bioimpedância (digitada), fotos de evolução | `lyfta_assessment` | 8083 |
   | `comms` | Chat (WS + REST), check-in/avaliação de treino, push (FCM), device tokens | `lyfta_comms` | 8084 |

2. **Projeto Go independente por serviço** (`backend/<svc>` com `go.mod` próprio),
   migrations próprias, deploy próprio. **Nenhuma FK entre bancos**; referência
   cruzada só por UUID. Joins entre domínios não existem — telas agregam no cliente
   ou via endpoint de composição no serviço dono da tela.
3. **Multi-tenancy (ADR-001) vale dentro de cada banco:** `tenant_id` + RLS em todas
   as tabelas de todos os serviços. ADR-001 não é revogado, é replicado por serviço.
4. **AuthN/AuthZ:** `identity` emite JWT **EdDSA (ed25519)** com claims do ADR-002;
   os demais serviços validam com a chave pública distribuída via env (JWKS endpoint
   é evolução futura). Service-to-service: token M2M estático via env no MVP.
5. **Comunicação entre serviços:** HTTP síncrono interno onde precisar (ex.: `comms`
   consulta `workout` para o push de treino pendente). Eventos assíncronos, quando
   surgirem, usam outbox por serviço + Redis pub/sub — o padrão do ADR-006 sobrevive
   *dentro* de cada serviço.
6. **Sem API gateway no MVP.** O app Flutter conhece as 4 base URLs via configuração;
   CORS configurado por serviço. Gateway/BFF é decisão futura se a composição doer.
7. **E-mails transacionais** (convite, recuperação de senha): **Resend**, encapsulado
   no `identity` (`RESEND_API_KEY` via env). Nenhum outro serviço envia e-mail.

## Consequências

- **Custo aceito conscientemente:** 4 pipelines de migração/deploy, agregações
  cross-domínio viram chamadas de API (o dashboard do 2.0 pagará esse preço), e
  transações atômicas entre domínios não existem — fluxos multi-serviço precisam ser
  idempotentes e tolerar eventual consistency.
- Benefício direto: o split futuro em repositórios é mover pastas, não desenhar
  fronteiras — as fronteiras já nasceram desenhadas.
- O ADR-006 fica **superado**; seu padrão outbox permanece válido como mecânica
  interna de cada serviço.
- Infra local: Postgres local do dev (4 bancos), Redis e MinIO via Docker Compose.
