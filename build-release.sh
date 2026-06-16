#!/usr/bin/env bash
#
# build-release.sh — Pipeline de release do Lume em um comando
#
#   1) Compila o app (xcodebuild, Release) → Lume.app
#   2) Gera o .dmg custom (fundo com as cores da marca + atalho do Applications)
#   3) Entrega o arquivo final nomeado com a versão: Lume-<versão>.dmg
#
# Uso:
#   ./build-release.sh                 # build + dmg
#   ./build-release.sh --no-clean      # não apaga o build anterior (mais rápido)
#
set -euo pipefail
cd "$(dirname "$0")"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "✖ Rode no macOS (precisa do Xcode)."; exit 1
fi
command -v xcodebuild >/dev/null || { echo "✖ xcodebuild não encontrado (instale o Xcode)."; exit 1; }

SCHEME="Lume"
PROJECT="Lume.xcodeproj"
CONFIG="Release"
BUILD_DIR="$PWD/build"
APP="$BUILD_DIR/Build/Products/$CONFIG/Lume.app"

if [[ "${1:-}" != "--no-clean" ]]; then
  echo "▶ Limpando build anterior…"
  rm -rf "$BUILD_DIR"
fi

echo "▶ Compilando ($CONFIG)… isso pode levar alguns minutos."
set -o pipefail
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$BUILD_DIR" \
  -destination 'generic/platform=macOS' \
  clean build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
  | { command -v xcbeautify >/dev/null 2>&1 && xcbeautify || cat; }

if [[ ! -d "$APP" ]]; then
  echo "✖ .app não encontrado em: $APP"
  echo "  Verifique se o scheme '$SCHEME' compila no Xcode."
  exit 1
fi
echo "✔ App compilado: $APP"

# ── DMG custom ───────────────────────────────────────────────────────────────
# Reusa o build-dmg.sh: gera o fundo (gradiente da logo) e nomeia automaticamente
# o arquivo final como Lume-<versão>.dmg (versão lida do Info.plist do app).
echo "▶ Gerando o DMG custom…"
./build-dmg.sh "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo "")"
DMG="Lume${VERSION:+-$VERSION}.dmg"
echo ""
echo "✅ Release pronto:"
echo "   • App: $APP"
echo "   • DMG: $PWD/$DMG"
