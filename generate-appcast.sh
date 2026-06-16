#!/usr/bin/env bash
#
# generate-appcast.sh — Gera/atualiza e assina (EdDSA) o appcast.xml do Sparkle
#
# Uso:
#   ./generate-appcast.sh Lume-1.2.0.dmg [vTAG]
#
# - Localiza o binário generate_appcast do Sparkle (vindo do pacote SPM)
# - Lê a versão de dentro do .dmg e assina com a chave privada (no Keychain)
# - Aponta o download para o asset do release no GitHub: .../releases/download/<TAG>/<arquivo>
# - Escreve/atualiza ./appcast.xml (commite na branch main = SUFeedURL)
#
set -euo pipefail

GH_OWNER="sbacaro"
GH_REPO="Lume"

DMG="${1:-}"
if [[ -z "$DMG" || ! -f "$DMG" ]]; then
  echo "✖ Informe o .dmg: ./generate-appcast.sh Lume-1.2.0.dmg [vTAG]"; exit 1
fi
DMG="$(cd "$(dirname "$DMG")" && pwd)/$(basename "$DMG")"

# Tag do release (default: v + versão extraída do nome do arquivo, ex.: Lume-1.2.0.dmg -> v1.2.0)
TAG="${2:-}"
if [[ -z "$TAG" ]]; then
  ver="$(basename "$DMG" | sed -E 's/^.*-([0-9]+\.[0-9]+(\.[0-9]+)?)\.dmg$/\1/')"
  TAG="v${ver}"
fi
echo "▶ Release tag: $TAG"

# Localiza o generate_appcast (artefato do pacote Sparkle no DerivedData)
GEN="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
        -path '*/artifacts/sparkle/Sparkle/bin/generate_appcast' 2>/dev/null | head -1 || true)"
if [[ -z "$GEN" ]]; then
  echo "✖ Não encontrei o 'generate_appcast'."
  echo "  1) Adicione o pacote Sparkle ao target (veja SETUP_SPARKLE.md, passo 1)"
  echo "  2) Faça um build (⌘B) para o Xcode baixar os artefatos"
  echo "  3) Rode este script de novo"
  exit 1
fi
echo "✔ Sparkle: $GEN"

PREFIX="https://github.com/${GH_OWNER}/${GH_REPO}/releases/download/${TAG}/"

DIST="$(mktemp -d)"; trap 'rm -rf "$DIST"' EXIT
cp "$DMG" "$DIST/"
# preserva entradas antigas do appcast existente
[[ -f appcast.xml ]] && cp appcast.xml "$DIST/appcast.xml"

echo "▶ Gerando e assinando o appcast…"
"$GEN" "$DIST" --download-url-prefix "$PREFIX"

cp "$DIST/appcast.xml" appcast.xml
echo ""
echo "✅ appcast.xml atualizado."
echo "   Agora:"
echo "   1) Anexe '$(basename "$DMG")' como asset do release $TAG no GitHub"
echo "   2) git add appcast.xml && git commit -m \"appcast ${TAG}\" && git push"
