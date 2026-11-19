# Imagem de um serviço Go do DÜO (ADR-022, plano docs/plan/staging S1).
# Um Dockerfile para os 5 serviços — o contexto é backend/ e o serviço vem
# do build-arg (nenhum serviço importa código de outro, ADR-013):
#
#   docker build --build-arg SERVICE=identity -t duo-identity backend/
#
# A imagem leva, além do binário:
#   /migrations  — SQL do serviço; o migrate roda como one-shot no deploy
#                  (o código não migra no boot):
#                  migrate -path /migrations -database "$MIGRATE_DATABASE_URL" up
#   /seed        — só workout: biblioteca global de exercícios (exige
#                  superusuário, ADR-010 §3), aplicada com o psql da imagem.

ARG GO_VERSION=1.26.4
ARG MIGRATE_VERSION=v4.19.1

FROM migrate/migrate:${MIGRATE_VERSION} AS migrate

FROM golang:${GO_VERSION}-alpine AS build
ARG SERVICE
RUN test -n "$SERVICE" || (echo "build-arg SERVICE é obrigatório" && false)
WORKDIR /src
COPY ${SERVICE}/go.mod ${SERVICE}/go.sum ./
RUN go mod download
COPY ${SERVICE}/ ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/api ./cmd/api \
 && mkdir -p /out/seed \
 && if [ -d seed ]; then cp -r seed/. /out/seed/; fi

FROM alpine:3.22
ARG SERVICE
# ca-certificates: Resend, FCM, Sentry e o S3 público por HTTPS.
# psql só onde há seed (workout).
COPY --from=build /out/seed /seed
RUN apk add --no-cache ca-certificates \
 && if [ -n "$(ls -A /seed)" ]; then apk add --no-cache postgresql17-client; fi \
 && addgroup -S duo && adduser -S -G duo -H duo
COPY --from=migrate /usr/local/bin/migrate /usr/local/bin/migrate
COPY ${SERVICE}/migrations /migrations
COPY --from=build /out/api /usr/local/bin/api
USER duo
ENV SERVICE=${SERVICE}
ENTRYPOINT ["/usr/local/bin/api"]
