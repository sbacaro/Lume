#!/usr/bin/env bash
#
# set-version.sh — Define a versão do Lume na FONTE ÚNICA (Version.xcconfig)
#
# Tudo (app/About, build, DMG, atualização) deriva deste arquivo. Edite só por aqui.
#
# Uso:
#   ./set-version.sh                 # mostra a versão atual
#   ./set-version.sh 1.3.1           # nova versão; build = atual + 1
#   ./set-version.sh 1.4.0 7         # nova versão e build explícitos
#
set -euo pipefail
cd "$(dirname "$0")"
CFG="Version.xcconfig"
[[ -f "$CFG" ]] || { echo "✖ $CFG não encontrado."; exit 1; }

read_kv() { grep -E "^$1" "$CFG" | sed -E 's/.*= *//' | tr -d ' '; }

CUR_VER="$(read_kv MARKETING_VERSION)"
CUR_BUILD="$(read_kv CURRENT_PROJECT_VERSION)"

VER="${1:-}"
if [[ -z "$VER" ]]; then
  echo "Versão atual: ${CUR_VER} (build ${CUR_BUILD})"
  echo "Uso: ./set-version.sh <versão> [build]"
  exit 0
fi

# valida formato X.Y ou X.Y.Z
if ! [[ "$VER" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "✖ Versão inválida: '$VER' (use X.Y ou X.Y.Z)"; exit 1
fi

BUILD="${2:-$(( ${CUR_BUILD:-0} + 1 ))}"

# BSD sed (macOS)
sed -i '' -E "s/^MARKETING_VERSION = .*/MARKETING_VERSION = ${VER}/"        "$CFG"
sed -i '' -E "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = ${BUILD}/" "$CFG"

echo "✔ Versão atualizada: ${CUR_VER} (build ${CUR_BUILD})  →  ${VER} (build ${BUILD})"
echo "  Recompile no Xcode para o app/About refletirem; os scripts já leem daqui."
