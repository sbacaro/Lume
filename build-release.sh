#!/usr/bin/env bash
#
# build-release.sh — Release do Lume em UM arquivo, fazendo tudo:
#
#   1) Lê a versão da FONTE ÚNICA (Version.xcconfig)
#   2) Compila o app (xcodebuild, Release) → Lume.app
#   3) Gera o DMG custom: fundo com o gradiente da marca + seta + atalho do Applications
#   4) Entrega o arquivo final: Lume-<versão>.dmg
#
# Uso:
#   ./build-release.sh                  # build + dmg
#   ./build-release.sh --no-clean       # reaproveita o build anterior
#   ./build-release.sh /caminho/Lume.app  # só o DMG, a partir de um .app pronto
#
set -euo pipefail
cd "$(dirname "$0")"

[[ "$(uname)" == "Darwin" ]] || { echo "✖ Rode no macOS."; exit 1; }

# ── Configuração ─────────────────────────────────────────────────────────────
APP_NAME="Lume"
VOL_NAME="Lume"
SCHEME="Lume"
PROJECT="Lume.xcodeproj"
CONFIG="Release"
BUILD_DIR="$PWD/build"
WIN_X=200; WIN_Y=120; WIN_W=660; WIN_H=420
ICON_SIZE=128
APP_X=165;  APP_Y=205
APPS_X=495; APPS_Y=205
# Cores da logo (LumeBrand.gradient) 0–255
C1="236,140,142"; C2="240,152,129"; C3="244,164,116"

# ── Versão (FONTE ÚNICA) ─────────────────────────────────────────────────────
if [[ -f Version.xcconfig ]]; then
  VERSION="$(grep -E '^MARKETING_VERSION' Version.xcconfig | sed -E 's/.*= *//' | tr -d ' ')"
else
  VERSION=""
fi

# ── 1/2) App: usa o passado como argumento, ou compila ───────────────────────
APP_ARG="${1:-}"
if [[ -n "$APP_ARG" && "$APP_ARG" != "--no-clean" && -d "$APP_ARG" ]]; then
  APP="$(cd "$(dirname "$APP_ARG")" && pwd)/$(basename "$APP_ARG")"
  echo "✔ Usando app existente: $APP"
else
  command -v xcodebuild >/dev/null || { echo "✖ xcodebuild não encontrado (instale o Xcode)."; exit 1; }
  APP="$BUILD_DIR/Build/Products/$CONFIG/$APP_NAME.app"
  [[ "${1:-}" == "--no-clean" ]] || { echo "▶ Limpando build anterior…"; rm -rf "$BUILD_DIR"; }
  echo "▶ Compilando ($CONFIG)… pode levar alguns minutos."
  set -o pipefail
  xcodebuild \
    -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
    -derivedDataPath "$BUILD_DIR" -destination 'generic/platform=macOS' \
    clean build \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
    | { command -v xcbeautify >/dev/null 2>&1 && xcbeautify || cat; }
  [[ -d "$APP" ]] || { echo "✖ .app não encontrado em: $APP"; exit 1; }
  echo "✔ App compilado: $APP"
fi

# versão de fallback: lê do próprio app se o xcconfig não existir
if [[ -z "$VERSION" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo "")"
fi
OUT_DMG="$PWD/${APP_NAME}${VERSION:+-$VERSION}.dmg"
rm -f "$OUT_DMG"

# ── Pastas temporárias ───────────────────────────────────────────────────────
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
BG_PNG="$WORK/background.png"

# ── 3a) Fundo (gradiente da marca + seta) em PNG puro (stdlib) ────────────────
echo "▶ Gerando o fundo…"
python3 - "$BG_PNG" "$WIN_W" "$WIN_H" "$C1" "$C2" "$C3" "$APP_Y" <<'PY'
import sys, zlib, struct
out, W, H = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
c1 = tuple(int(x) for x in sys.argv[4].split(","))
c2 = tuple(int(x) for x in sys.argv[5].split(","))
c3 = tuple(int(x) for x in sys.argv[6].split(","))
ay = int(sys.argv[7])
def lerp(a,b,t): return a+(b-a)*t
def grad(t):
    if t<0.5:
        u=t/0.5; return [lerp(c1[i],c2[i],u) for i in range(3)]
    u=(t-0.5)/0.5; return [lerp(c2[i],c3[i],u) for i in range(3)]
cx, cy = W//2, ay
def arrow(x,y):                       # seta apontando para a DIREITA
    shaft=(cx-46<=x<=cx+10) and (cy-6<=y<=cy+6)
    tip=cx+56; head=(cx+10<=x<=tip) and (abs(y-cy)<=(tip-x))
    return 0.40 if (shaft or head) else 0.0
raw=bytearray()
for y in range(H):
    raw.append(0)
    for x in range(W):
        t=(x/(W-1))*0.9+(y/(H-1))*0.1
        r,g,b=grad(min(max(t,0.0),1.0)); a=arrow(x,y)
        if a: r=r+(255-r)*a; g=g+(255-g)*a; b=b+(255-b)*a
        raw+=bytes((int(r)&255,int(g)&255,int(b)&255))
def chunk(t,d): return struct.pack(">I",len(d))+t+d+struct.pack(">I",zlib.crc32(t+d)&0xffffffff)
open(out,"wb").write(b'\x89PNG\r\n\x1a\n'
    +chunk(b'IHDR',struct.pack(">IIBBBBB",W,H,8,2,0,0,0))
    +chunk(b'IDAT',zlib.compress(bytes(raw),9))+chunk(b'IEND',b''))
PY

# ── 3b) DMG headless via dmgbuild (instala num venv se preciso) ───────────────
DMGBUILD=""
if command -v dmgbuild >/dev/null 2>&1; then
  DMGBUILD="dmgbuild"
else
  echo "▶ Preparando dmgbuild (venv temporário)…"
  if python3 -m venv "$WORK/venv" >/dev/null 2>&1 \
     && "$WORK/venv/bin/pip" install --quiet --disable-pip-version-check dmgbuild >/dev/null 2>&1; then
    DMGBUILD="$WORK/venv/bin/dmgbuild"
  fi
fi

if [[ -n "$DMGBUILD" ]]; then
  cat > "$WORK/settings.py" <<PYS
# -*- coding: utf-8 -*-
import os.path
app = "$APP"
appname = os.path.basename(app)
format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon_locations = {appname: ($APP_X, $APP_Y), "Applications": ($APPS_X, $APPS_Y)}
background = "$BG_PNG"
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
arrange_by = None
icon_size = $ICON_SIZE
text_size = 12
window_rect = (($WIN_X, $WIN_Y), ($WIN_W, $WIN_H))
PYS
  echo "▶ Criando o DMG ($(basename "$OUT_DMG"))…"
  "$DMGBUILD" -s "$WORK/settings.py" "$VOL_NAME" "$OUT_DMG"
  echo ""
  echo "✅ Release pronto:"
  echo "   • App: $APP"
  echo "   • DMG: $OUT_DMG  ($(du -h "$OUT_DMG" | cut -f1))"
  exit 0
fi

# ── 3c) Fallback nativo (hdiutil + AppleScript) ──────────────────────────────
echo "▶ dmgbuild indisponível — usando o método nativo (Finder)…"
STAGE="$WORK/stage"; MOUNT="$WORK/mnt"; RW="$WORK/rw.dmg"
mkdir -p "$STAGE/.background" "$MOUNT"
cp -R "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
cp "$BG_PNG" "$STAGE/.background/background.png"
hdiutil create -srcfolder "$STAGE" -volname "$VOL_NAME" -fs HFS+ -format UDRW -ov "$RW" -quiet
hdiutil attach "$RW" -mountpoint "$MOUNT" -noautoopen -quiet
ASERR="$(osascript 2>&1 <<OSA || true
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {$WIN_X, $WIN_Y, $((WIN_X+WIN_W)), $((WIN_Y+WIN_H+22))}
    set vo to the icon view options of container window
    set arrangement of vo to not arranged
    set icon size of vo to $ICON_SIZE
    set text size of vo to 12
    set background picture of vo to file ".background:background.png"
    set position of item "$APP_NAME.app" of container window to {$APP_X, $APP_Y}
    set position of item "Applications" of container window to {$APPS_X, $APPS_Y}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
)"
[[ -n "$ASERR" ]] && echo "⚠ Finder/AppleScript: $ASERR (autorize Automação → Finder, ou instale o dmgbuild)."
sync
hdiutil detach "$MOUNT" -quiet
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT_DMG" -quiet
echo ""
echo "✅ Release pronto:"
echo "   • App: $APP"
echo "   • DMG: $OUT_DMG  ($(du -h "$OUT_DMG" | cut -f1))"
