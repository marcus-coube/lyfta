# Guidelines — Backend Go

Complementa `001-arquitetura.md` (monólito modular) e os ADRs. Em conflito, o ADR vence.

## Layout

```
backend/
  cmd/api/main.go            # composição/DI manual, só wiring
  internal/
    auth/ tenant/ users/ workout/ running/ finance/ chat/ notification/
      domain/                # entidades, value objects, interfaces (ports)
      app/                   # casos de uso (services), transações
      infra/                 # postgres, redis, s3 (adapters)
      http/                  # handlers, DTOs, rotas do módulo
    platform/                # db pool, config, logger, middleware, outbox
  migrations/
```

- Módulo não importa `internal/` de outro módulo. Comunicação entre módulos: interface no domain de quem consome, ou evento via outbox (ADR-006).
- `domain` não importa nada de `infra`/`http`. Dependências apontam para dentro.

## Convenções

- `context.Context` é sempre o 1º parâmetro; todo I/O tem timeout.
- Erros: `fmt.Errorf("op: %w", err)`; erros de domínio como sentinels (`ErrStudentNotFound`) mapeados para HTTP em um único lugar. `panic` nunca em fluxo normal.
- Config só via env (12-factor), struct única em `platform/config`, validada no boot.
- Log estruturado com `log/slog`; sempre com `tenant_id` e `request_id` no contexto.

## HTTP / API

- Router: `chi` (ou stdlib `http.ServeMux` 1.22+). Rotas versionadas `/v1`.
- DTOs de request/response separados do domain; validação na borda (handler), regra de negócio no `app`.
- Erros de API em formato único (problem+json): `{code, message, details}`.
- Autenticação JWT curto + refresh rotativo (ver `008-api.md`); middleware injeta claims (user, tenant, role) no contexto.

## Banco

- `pgx` + `sqlc` (queries tipadas geradas; sem ORM pesado).
- Migrations com `golang-migrate`, versionadas no repo, nunca editadas após merge.
- **Toda query filtra por `tenant_id`** (ADR-001); repositório recebe tenant do contexto, nunca de parâmetro do cliente.
- Transação abre no caso de uso (`app`), não no repositório. Dinheiro em centavos/`int64` (ADR-007).

## Testes & qualidade

- Testes table-driven; domínio e casos de uso sem banco (mocks das interfaces).
- Integração de repositórios com testcontainers (Postgres real).
- `golangci-lint` no CI; `go vet` + `gofumpt` obrigatórios.
- Regra prática: caso de uso novo = teste novo no mesmo PR.
