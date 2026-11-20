#!/usr/bin/env bash
# Preparação ÚNICA da VPS para o duo-staging (plano S5, ADR-022). Rodar como
# root, uma vez; é idempotente (rodar de novo não troca segredos existentes).
#
#   sudo ./bootstrap-vps.sh staging.duotraining.app "ssh-ed25519 AAAA... duo-staging-ci"
#
# Faz SÓ isto, e nada fora disso:
#   1. confere memória livre (staging não pode empurrar produção para o swap);
#   2. cria o usuário `duo-deploy` (sem senha, grupo docker) com a chave
#      pública do CI no PRÓPRIO authorized_keys — o `deploy` dos outros
#      projetos não é tocado;
#   3. cria /opt/duo-staging (dono duo-deploy) e gera o .env com segredos
#      aleatórios feitos AQUI (nunca saem da VPS);
#   4. imprime o bloco do Caddyfile compartilhado — colar à mão (S5.7).
set -euo pipefail

BASE="${1:?uso: $0 <DUO_BASE> <chave pública do CI>}"
CI_PUBKEY="${2:?uso: $0 <DUO_BASE> <chave pública do CI>}"
USER_NAME=duo-deploy
DIR=/opt/duo-staging
MIN_AVAIL_MB=2048

[ "$(id -u)" -eq 0 ] || { echo "rode como root"; exit 1; }
case "$CI_PUBKEY" in ssh-ed25519\ *|ssh-rsa\ *) ;; *) echo "chave pública inválida"; exit 1;; esac

echo "==> memória"
avail=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
free -h
if [ "$avail" -lt "$MIN_AVAIL_MB" ] && [ "${FORCE:-}" != 1 ]; then
  echo "MemAvailable ${avail} MB < ${MIN_AVAIL_MB} MB — revise antes (FORCE=1 ignora)"; exit 1
fi

echo "==> usuário $USER_NAME"
if ! id "$USER_NAME" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "DUO staging deploy (CI)" "$USER_NAME"
fi
usermod -aG docker "$USER_NAME"
home=$(getent passwd "$USER_NAME" | cut -d: -f6)
install -d -m 700 -o "$USER_NAME" -g "$USER_NAME" "$home/.ssh"
touch "$home/.ssh/authorized_keys"
grep -qxF "$CI_PUBKEY" "$home/.ssh/authorized_keys" || echo "$CI_PUBKEY" >> "$home/.ssh/authorized_keys"
chown "$USER_NAME:$USER_NAME" "$home/.ssh/authorized_keys"
chmod 600 "$home/.ssh/authorized_keys"

echo "==> $DIR"
install -d -m 750 -o "$USER_NAME" -g "$USER_NAME" "$DIR"

if [ -f "$DIR/.env" ]; then
  echo ".env já existe — mantido (segredos não são regenerados)"
else
  hex() { openssl rand -hex 32; }
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  openssl genpkey -algorithm ed25519 -out "$tmp/priv.pem" 2>/dev/null
  openssl pkey -in "$tmp/priv.pem" -pubout -out "$tmp/pub.pem" 2>/dev/null
  pem() { awk '{printf "%s\\n", $0}' "$1"; }
  umask 077
  cat > "$DIR/.env" <<EOF
# Gerado por bootstrap-vps.sh em $(date -I). Modelo: .env.example.
DUO_BASE=$BASE
PUBLIC_SCHEME=https
PUBLIC_PORT=
TAG=staging

POSTGRES_PASSWORD=$(hex)
DUO_APP_PASSWORD=$(hex)
REDIS_PASSWORD=$(hex)
MINIO_ROOT_USER=duo-staging
MINIO_ROOT_PASSWORD=$(hex)

JWT_PRIVATE_KEY=$(pem "$tmp/priv.pem")
JWT_PUBLIC_KEY=$(pem "$tmp/pub.pem")
INTERNAL_TOKEN=$(hex)

# Preencher com a chave do Resend (domínio verificado) antes de convidar testadores.
RESEND_API_KEY=
MAIL_FROM=DÜO <no-reply@duotraining.app>
TERMS_VERSION=2026-11-v4

SENTRY_DSN=
SENTRY_RELEASE=
EOF
  chown "$USER_NAME:$USER_NAME" "$DIR/.env"
  chmod 600 "$DIR/.env"
  echo ".env gerado"
fi

cat <<EOF

==> pronto. Próximos passos (plano S5):

1) GHCR como $USER_NAME (PAT clássico só com read:packages):
     su - $USER_NAME -c 'docker login ghcr.io -u marcus-coube'

2) Colar no FIM de /opt/edge/Caddyfile (backup antes), depois validar e recarregar:
     cp /opt/edge/Caddyfile /opt/edge/Caddyfile.bak.\$(date +%F)
     docker exec edge-caddy-1 caddy validate --config /etc/caddy/Caddyfile
     docker exec edge-caddy-1 caddy reload   --config /etc/caddy/Caddyfile

# ============================ DÜO — STAGING (ADR-022, repo lyfta) ============================
# Cloudflare DNS-only (nuvem cinza) → Let's Encrypt automático. Roteamento interno
# no gateway do stack (/opt/duo-staging); só este bloco vive aqui.
app.$BASE, identity.$BASE, workout.$BASE, assessment.$BASE,
comms.$BASE, billing.$BASE, media.$BASE {
	encode zstd gzip
	log {
		output stdout
		format console
	}
	reverse_proxy duo-staging-gateway:8080
}

3) Primeiro deploy: rodar o workflow "Deploy duo-staging" no GitHub
   (ou git push origin main:staging).
EOF
