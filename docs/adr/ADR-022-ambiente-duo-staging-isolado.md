# ADR-022 — Ambiente `duo-staging` isolado na VPS compartilhada

**Status:** Proposto (2026-11-16)
**Data:** 2026-11-16
**Complementa:** [ADR-009](ADR-009-infra-vps.md) §2 (staging no mesmo host).

## Contexto

Antes das lojas (ADR-015), testadores reais vão validar o DÜO pelo **web**. O
host é a VPS que já roda o mh-blog (produção) e o ecoprobe-gestao (staging e
produção) — Hostinger KVM 2, 2 vCPU / 8 GB, Docker Compose, Caddy em
`/opt/edge` dono de 80/443, Postgres e Redis **compartilhados** em `/opt/data`
(fonte viva: `vps-infra.md` no repo ecoprobe-gestao). O PO exige isolamento
total: nada das outras aplicações pode ser tocado, **exceto** o
`/opt/edge/Caddyfile`, que é a única porta de entrada.

## Decisão

1. **Uma pasta, um projeto Compose:** `/opt/duo-staging/`, project name
   `duo-staging`. Derrubar o ambiente (`docker compose down -v`) não alcança
   nada fora dele.
2. **Dados próprios, não a camada `/opt/data`:** Postgres 17, Redis 7 e MinIO
   são contêineres **do próprio stack**, com volumes próprios. Os 5 bancos
   `duo_*` (ADR-013) vivem nesse Postgres; a role `duo_app` (RLS, ADR-001) é
   criada pelas migrations ali, sem colidir com roles de outros projetos.
3. **Rede privada + um único ponto na `edge`:** tudo roda na rede
   `duo-staging` (bridge própria). Só o contêiner `gateway` (Caddy interno)
   também entra na rede externa `edge`, com alias **`duo-staging-gateway`**.
   Nenhum contêiner publica `ports:`.
4. **Um bloco no Caddyfile compartilhado:** todos os hosts do ambiente apontam
   para `duo-staging-gateway:8080`; o roteamento por host (app web, 5 APIs,
   mídia) fica no Caddyfile **do gateway**, versionado aqui. Mudanças futuras
   de roteamento não tocam o `/opt/edge`.
5. **Um subdomínio por serviço** (`identity.`, `workout.`, `assessment.`,
   `comms.`, `billing.`, `media.`, `app.`): as APIs compartilham prefixos
   (`/v1/me/...`) e o WebSocket do app usa caminho fixo `/ws` — subdomínio
   evita qualquer mudança de código. DNS-only (nuvem cinza) + Let's Encrypt,
   o regime já usado pelo staging do ecoprobe.
6. **Imagens no GHCR, buildadas no GitHub Actions;** a VPS só faz `pull`
   (2 vCPU não comportam build). Migrations rodam **one-shot** antes do `up`
   (o código não migra no boot).
7. **Teto de recursos:** `mem_limit` e `cpus` em todo contêiner; soma ≤ 1,3 GB
   de RAM e o stack nunca disputa CPU com produção (`cpus` ≤ 0,5 por
   contêiner).

## Consequências

- Custa ~1 GB de RAM a mais do que usar `/opt/data` — preço aceito pelo
  isolamento; conferir `free -h` antes do primeiro `up`.
- Backup **não** entra no `backup` do `/opt/data`; se o staging guardar dados
  de testadores, o backup é um serviço do próprio stack (plano S7).
- O comms apaga mídia no MinIO pelo endpoint público (`media.`), em
  *hairpin* pela `edge`: o presign do SDK S3 assina com o mesmo host que o
  servidor usa.
- Produção, quando vier, segue o mesmo desenho em `/opt/duo-prod/` com outro
  alias de gateway — ou revisita o ADR-009 se sair da VPS compartilhada.
