# Gateway do duo-staging: Caddy + build do Flutter web (ADR-022, plano S2).
# O build web acontece ANTES (no CI ou na máquina) e entra pelo contexto
# nomeado `web` — as URLs das APIs ficam embutidas pelo --dart-define:
#
#   (cd app && flutter build web --release --dart-define=IDENTITY_BASE_URL=...)
#   docker build --build-context web=app/build/web \
#     -t duo-gateway deploy/duo-staging/gateway
FROM caddy:2.10-alpine
COPY Caddyfile /etc/caddy/Caddyfile
COPY --from=web . /srv/web
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8081/healthz || exit 1
