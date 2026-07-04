#!/usr/bin/env bash
# Guard de CI (ADR-011 §5): nenhuma string literal de UI fora do design
# system. Aproximação até termos custom_lint — procura `Text('...')` /
# `Text("...")` literal em lib/, excluindo core/design_system/ (fonte da
# verdade de estilo, onde literais só aparecem em exemplos/testes internos)
# e os arquivos gerados de l10n.
#
# Uso: tool/check_hardcoded_strings.sh (rodar a partir de app/, ou de
# qualquer lugar — o script resolve o próprio diretório).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$(dirname "$script_dir")"
lib_dir="$app_dir/lib"

matches="$(grep -rnE "Text\((['\"])" "$lib_dir" \
  --include="*.dart" \
  | grep -v "/core/design_system/" \
  | grep -v "/core/l10n/gen/" \
  || true)"

if [ -n "$matches" ]; then
  echo "Strings literais de UI encontradas fora do design system (ADR-011):"
  echo "$matches"
  echo
  echo "Mova a string para os ARBs em lib/core/l10n/arb/ e use AppLocalizations.of(context)."
  exit 1
fi

echo "OK: nenhuma string literal de UI fora do design system."
