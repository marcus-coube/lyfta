#!/usr/bin/env bash
# Gera um par de chaves EdDSA (ed25519) para assinar/validar o JWT do identity
# (backend/README.md, P0.3). Imprime os dois PEMs em stdout, prontos para colar
# em JWT_PRIVATE_KEY / JWT_PUBLIC_KEY nos .env de cada serviço — nunca commitar
# o par gerado.
#
# Uso: backend/scripts/gen-keys.sh
set -euo pipefail

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

openssl genpkey -algorithm ed25519 -out "$tmpdir/private.pem" >/dev/null 2>&1
openssl pkey -in "$tmpdir/private.pem" -pubout -out "$tmpdir/public.pem" >/dev/null 2>&1

echo "# Cole em JWT_PRIVATE_KEY (só no identity, nunca compartilhar):"
echo "JWT_PRIVATE_KEY=\"$(awk '{printf "%s\\n", $0}' "$tmpdir/private.pem")\""
echo
echo "# Cole em JWT_PUBLIC_KEY (identity e demais serviços, para validar):"
echo "JWT_PUBLIC_KEY=\"$(awk '{printf "%s\\n", $0}' "$tmpdir/public.pem")\""
