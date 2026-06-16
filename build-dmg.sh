#!/usr/bin/env bash
#
# build-dmg.sh — Cria um .dmg personalizado do Lume (totalmente automático)
#
# - Fundo com o gradiente da logo (coral → pêssego) e uma seta "arraste aqui"
# - Atalho da pasta /Applications ao lado do app, para instalar arrastando
# - Layout aplicado de forma HEADLESS (escreve o .DS_Store direto via dmgbuild),
#   sem depender de permissão de automação do Finder (que falha em silêncio no
#   macOS recente). Se o dmgbuild não puder ser instalado, cai para o método
#   nativo via AppleScript.
#
# Uso:
#   ./build-dmg.sh [caminho/para/Lume.app] [saida.dmg]
#
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuração
# ─────────────────────────────────────────────────────────────────────────────
APP_NAME="Lume"
VOL_NAME="Lume"
WIN_X=200; WIN_Y=120          # posição da janela
WIN_W=660; WIN_H=420          # tamanho da janela / do fundo
ICON_SIZE=128
APP_X=165;  APP_Y=205         # posição do ícone do app
APPS_X=495; APPS_Y=205        # posição do atalho de Applications

# Cores da logo (LumeBrand.gradient) em 0–255
C1="236,140,142"   # coral   #EC8C8E
C2="240,152,129"   # pêssego #F09881
C3="244,164,116"   # laranja #F4A474

# ─────────────────────────────────────────────────────────────────────────────
# Pré-requisito mínimo
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$(uname)" != "Darwin" ]]; then
  echo "✖ Este script precisa rodar no macOS."; exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 1) Localiza o .app
# ─────────────────────────────────────────────────────────────────────────────
APP_PATH="${1:-}"
if [[ -z "$APP_PATH" ]]; then
  echo "▶ Procurando ${APP_NAME}.app no DerivedData…"
  APP_PATH="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
      -type d -name "${APP_NAME}.app" -path "*/Build/Products/*" 2>/dev/null \
      | xargs -I{} stat -f "%m %N" {} 2>/dev/null \
      | sort -rn | head -1 | cut -d' ' -f2- || true)"
fi
if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "✖ Não encontrei o ${APP_NAME}.app."
  echo "  Faça um build no Xcode (Product → Archive ou ⌘B) e rode:"
  echo "      ./build-dmg.sh /caminho/para/${APP_NAME}.app"
  exit 1
fi
APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"  # absoluto
echo "✔ App: $APP_PATH"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
            "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "")"
OUT_DMG="${2:-${APP_NAME}${VERSION:+-$VERSION}.dmg}"
# caminho absoluto de saída
OUT_DIR="$(cd "$(dirname "$OUT_DMG")" 2>/dev/null && pwd || pwd)"
OUT_DMG="$OUT_DIR/$(basename "$OUT_DMG")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BG_PNG="$WORK/background.png"

# ─────────────────────────────────────────────────────────────────────────────
# 2) Gera o fundo (gradiente + seta) em PNG puro (stdlib do python3)
# ─────────────────────────────────────────────────────────────────────────────
echo "▶ Gerando o fundo…"
python3 - "$BG_PNG" "$WIN_W" "$WIN_H" "$C1" "$C2" "$C3" "$APP_Y" <<'PY'
import sys, zlib, struct
out, W, H = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
c1 = tuple(int(x) for x in sys.argv[4].split(","))
c2 = tuple(int(x) for x in sys.argv[5].split(","))
c3 = tuple(int(x) for x in sys.argv[6].split(","))
ay = int(sys.argv[7])
def lerp(a, b, t): return a + (b - a) * t
def grad(t):
    if t < 0.5:
        u = t / 0.5; return [lerp(c1[i], c2[i], u) for i in range(3)]
    u = (t - 0.5) / 0.5; return [lerp(c2[i], c3[i], u) for i in range(3)]
cx, cy = W // 2, ay
def arrow_alpha(x, y):                       # seta apontando para a DIREITA
    shaft = (cx - 46 <= x <= cx + 10) and (cy - 6 <= y <= cy + 6)
    tip = cx + 56
    head = (cx + 10 <= x <= tip) and (abs(y - cy) <= (tip - x))
    return 0.40 if (shaft or head) else 0.0
raw = bytearray()
for y in range(H):
    raw.append(0)
    for x in range(W):
        t = (x / (W - 1)) * 0.9 + (y / (H - 1)) * 0.1
        r, g, b = grad(min(max(t, 0.0), 1.0))
        a = arrow_alpha(x, y)
        if a:
            r = r + (255 - r) * a; g = g + (255 - g) * a; b = b + (255 - b) * a
        raw += bytes((int(r) & 255, int(g) & 255, int(b) & 255))
def chunk(typ, data):
    return (struct.pack(">I", len(data)) + typ + data
            + struct.pack(">I", zlib.crc32(typ + data) & 0xffffffff))
open(out, "wb").write(
    b'\x89PNG\r\n\x1a\n'
    + chunk(b'IHDR', struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
    + chunk(b'IDAT', zlib.compress(bytes(raw), 9))
    + chunk(b'IEND', b''))
PY

rm -f "$OUT_DMG"

# ─────────────────────────────────────────────────────────────────────────────
# 3) Caminho principal: dmgbuild (headless, escreve o layout sem o Finder)
# ─────────────────────────────────────────────────────────────────────────────
DMGBUILD=""
if command -v dmgbuild >/dev/null 2>&1; then
  DMGBUILD="dmgbuild"
else
  echo "▶ Preparando dmgbuild (ambiente isolado)…"
  if python3 -m venv "$WORK/venv" >/dev/null 2>&1 \
     && "$WORK/venv/bin/pip" install --quiet --disable-pip-version-check dmgbuild >/dev/null 2>&1; then
    DMGBUILD="$WORK/venv/bin/dmgbuild"
  fi
fi

if [[ -n "$DMGBUILD" ]]; then
  cat > "$WORK/settings.py" <<PYS
# -*- coding: utf-8 -*-
import os.path
app = "$APP_PATH"
appname = os.path.basename(app)
format = "UDZO"
compression_level = 9
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
  echo "▶ Criando o DMG (dmgbuild)…"
  "$DMGBUILD" -s "$WORK/settings.py" "$VOL_NAME" "$OUT_DMG"
  echo ""
  echo "✅ Pronto: $OUT_DMG  ($(du -h "$OUT_DMG" | cut -f1))"
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# 4) Fallback: método nativo via hdiutil + AppleScript
#    (requer permitir "Terminal controlar o Finder" em Ajustes do Sistema →
#     Privacidade e Segurança → Automação, na primeira execução)
# ─────────────────────────────────────────────────────────────────────────────
echo "▶ dmgbuild indisponível — usando o método nativo (Finder)…"
STAGE="$WORK/stage"; MOUNT="$WORK/mnt"; RW_DMG="$WORK/rw.dmg"
mkdir -p "$STAGE/.background" "$MOUNT"
cp -R "$APP_PATH" "$STAGE/${APP_NAME}.app"
ln -s /Applications "$STAGE/Applications"
cp "$BG_PNG" "$STAGE/.background/background.png"

hdiutil create -srcfolder "$STAGE" -volname "$VOL_NAME" -fs HFS+ -format UDRW -ov "$RW_DMG" -quiet
hdiutil attach "$RW_DMG" -mountpoint "$MOUNT" -noautoopen -quiet

ASERR="$(osascript 2>&1 <<OSA || true
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {$WIN_X, $WIN_Y, $((WIN_X + WIN_W)), $((WIN_Y + WIN_H + 22))}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to $ICON_SIZE
    set text size of theViewOptions to 12
    set background picture of theViewOptions to file ".background:background.png"
    set position of item "${APP_NAME}.app" of container window to {$APP_X, $APP_Y}
    set position of item "Applications" of container window to {$APPS_X, $APPS_Y}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
)"
if [[ -n "$ASERR" ]]; then
  echo "⚠ Aviso do AppleScript: $ASERR"
  echo "  Se o fundo não aparecer, autorize: Ajustes do Sistema → Privacidade e"
  echo "  Segurança → Automação → seu terminal → Finder. Ou instale o dmgbuild:"
  echo "      python3 -m pip install --user dmgbuild"
fi
sync
hdiutil detach "$MOUNT" -quiet
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUT_DMG" -quiet
echo ""
echo "✅ Pronto: $OUT_DMG  ($(du -h "$OUT_DMG" | cut -f1))"
