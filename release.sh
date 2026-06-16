#!/usr/bin/env bash
#
# release.sh — Release do Lume em UM comando, fazendo TUDO sozinho:
#
#   1) Versao na FONTE UNICA (Version.xcconfig). Opcional: passar nova versao.
#   2) Compila o app (xcodebuild, Release) -> Lume.app
#   3) Gera o DMG custom com o Lume.app DENTRO (fundo no gradiente da marca +
#      atalho do Applications para arrastar e soltar)
#   4) Commit + push do que estiver pendente
#   5) Cria e empurra a tag vX.Y.Z
#   6) Cria/atualiza o release no GitHub, anexa o DMG e marca como "latest"
#
# Autocontido: NAO depende de outros scripts. Sem Homebrew nem gh obrigatorios
# (usa git + python3 do macOS). Se o gh estiver instalado e autenticado, usa ele.
#
# Uso:
#   ./release.sh                 # usa a versao atual do Version.xcconfig
#   ./release.sh 1.3.4           # define nova versao (build = atual + 1) e publica
#   ./release.sh 1.4.0 9         # nova versao e build explicitos
#   ./release.sh --no-build      # reaproveita o DMG ja gerado
#   ./release.sh --draft         # cria como rascunho (nao vira latest)
#   ./release.sh --save-token    # salva/atualiza o token do GitHub no Keychain e sai
#   ./release.sh --forget-token  # remove o token do Keychain
#
# Observacao: nao usamos `set -u` de proposito. O arquivo fica num Drive
# sincronizado e variaveis sempre definidas (TAG, VERSION...) nao precisam de
# nounset; evita abortos espurios de "unbound variable".
set -eo pipefail
cd "$(dirname "$0")"
[ "$(uname)" = "Darwin" ] || { echo "Rode no macOS."; exit 1; }

# ---- Configuracao ----------------------------------------------------------
APP_NAME="Lume"
VOL_NAME="Lume"
SCHEME="Lume"
PROJECT="Lume.xcodeproj"
CONFIG="Release"
CFG="Version.xcconfig"
BUILD_DIR="$PWD/build"
KC_SERVICE="lume-github-token"
WIN_X=200; WIN_Y=120; WIN_W=660; WIN_H=420
ICON_SIZE=128; APP_X=165; APP_Y=205; APPS_X=495; APPS_Y=205
C1="236,140,142"; C2="240,152,129"; C3="244,164,116"

# ---- Flags / argumentos ----------------------------------------------------
NO_BUILD=0; DRAFT=0; NEW_VER=""; NEW_BUILD=""
for a in "$@"; do
  case "$a" in
    --no-build) NO_BUILD=1 ;;
    --draft)    DRAFT=1 ;;
    --save-token)
        printf "Cole o token do GitHub (escopo repo): "; read -rs _T; echo
        [ -n "$_T" ] && security add-generic-password -U -a "$USER" -s "$KC_SERVICE" -w "$_T" \
          && echo "Token salvo no Keychain." || echo "Nada salvo."; exit 0 ;;
    --forget-token)
        security delete-generic-password -s "$KC_SERVICE" >/dev/null 2>&1 \
          && echo "Token removido." || echo "Nenhum token salvo."; exit 0 ;;
    [0-9]*.[0-9]*) if [ -z "$NEW_VER" ]; then NEW_VER="$a"; else NEW_BUILD="$a"; fi ;;
    [0-9]*)        NEW_BUILD="$a" ;;
    *) echo "Argumento desconhecido: $a"; exit 1 ;;
  esac
done

[ -f "$CFG" ] || { echo "$CFG nao encontrado."; exit 1; }
read_kv() { grep -E "^$1" "$CFG" | sed -E 's/.*= *//' | tr -d ' '; }

# ---- 1) Versao (FONTE UNICA) ----------------------------------------------
if [ -n "$NEW_VER" ]; then
  case "$NEW_VER" in
    [0-9]*.[0-9]*) : ;;
    *) echo "Versao invalida: '$NEW_VER'"; exit 1 ;;
  esac
  CUR_BUILD="$(read_kv CURRENT_PROJECT_VERSION)"
  [ -n "$NEW_BUILD" ] || NEW_BUILD=$(( ${CUR_BUILD:-0} + 1 ))
  sed -i '' -E "s/^MARKETING_VERSION = .*/MARKETING_VERSION = ${NEW_VER}/"               "$CFG"
  sed -i '' -E "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = ${NEW_BUILD}/" "$CFG"
  echo "Versao definida: ${NEW_VER} (build ${NEW_BUILD})"
fi

VERSION="$(read_kv MARKETING_VERSION)"
BUILD="$(read_kv CURRENT_PROJECT_VERSION)"
[ -n "$VERSION" ] || { echo "Nao consegui ler a versao de $CFG."; exit 1; }
TAG="v$VERSION"
OUT_DMG="$PWD/${APP_NAME}-${VERSION}.dmg"
APP="$BUILD_DIR/Build/Products/$CONFIG/$APP_NAME.app"
# PKG descontinuado: o app vai DENTRO do DMG. Remove .pkg antigo desta versao.
rm -f "$PWD/${APP_NAME}-${VERSION}.pkg"

REMOTE="$(git remote get-url origin 2>/dev/null || echo "")"
SLUG="$(echo "$REMOTE" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
[ -n "$SLUG" ] || SLUG="sbacaro/Lume"
OWNER="${SLUG%%/*}"; REPO="${SLUG##*/}"
echo "Repo: $OWNER/$REPO   Versao: $VERSION (build $BUILD)   Tag: $TAG"

# ---- 2) Compilar o app -----------------------------------------------------
if [ "$NO_BUILD" = "1" ] && [ -d "$APP" ]; then
  echo "Reaproveitando app: $APP"
else
  command -v xcodebuild >/dev/null || { echo "xcodebuild nao encontrado (instale o Xcode)."; exit 1; }
  echo "Compilando ($CONFIG)... pode levar alguns minutos."
  rm -rf "$BUILD_DIR"
  xcodebuild \
    -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
    -derivedDataPath "$BUILD_DIR" -destination 'generic/platform=macOS' \
    clean build \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
    | { command -v xcbeautify >/dev/null 2>&1 && xcbeautify || cat; }
  [ -d "$APP" ] || { echo ".app nao encontrado em: $APP"; exit 1; }
  echo "App compilado: $APP"
fi

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# ---- 3) DMG (com o Lume.app dentro) ----------------------------------------
if [ "$NO_BUILD" = "1" ] && [ -f "$OUT_DMG" ]; then
  echo "Reaproveitando DMG: $OUT_DMG"
else
  rm -f "$OUT_DMG"
  BG_PNG="$WORK/background.png"
  echo "Gerando o fundo do DMG..."
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
def arrow(x,y):
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

  DMGBUILD=""
  if command -v dmgbuild >/dev/null 2>&1; then
    DMGBUILD="dmgbuild"
  else
    echo "Preparando dmgbuild (venv temporario)..."
    if python3 -m venv "$WORK/venv" >/dev/null 2>&1 \
       && "$WORK/venv/bin/pip" install --quiet --disable-pip-version-check dmgbuild >/dev/null 2>&1; then
      DMGBUILD="$WORK/venv/bin/dmgbuild"
    fi
  fi

  if [ -n "$DMGBUILD" ]; then
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
    echo "Criando o DMG..."
    "$DMGBUILD" -s "$WORK/settings.py" "$VOL_NAME" "$OUT_DMG"
  else
    echo "dmgbuild indisponivel — metodo nativo (hdiutil + Finder)..."
    STAGE="$WORK/stage"; MOUNT="$WORK/mnt"; RW="$WORK/rw.dmg"
    mkdir -p "$STAGE/.background" "$MOUNT"
    cp -R "$APP" "$STAGE/$APP_NAME.app"
    ln -s /Applications "$STAGE/Applications"
    cp "$BG_PNG" "$STAGE/.background/background.png"
    hdiutil create -srcfolder "$STAGE" -volname "$VOL_NAME" -fs HFS+ -format UDRW -ov "$RW" -quiet
    hdiutil attach "$RW" -mountpoint "$MOUNT" -noautoopen -quiet
    osascript >/dev/null 2>&1 <<OSA || true
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
    set background picture of vo to file ".background:background.png"
    set position of item "$APP_NAME.app" of container window to {$APP_X, $APP_Y}
    set position of item "Applications" of container window to {$APPS_X, $APPS_Y}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
    sync; hdiutil detach "$MOUNT" -quiet
    hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT_DMG" -quiet
  fi
  echo "DMG: $OUT_DMG ($(du -h "$OUT_DMG" | cut -f1))  - Lume.app esta dentro do DMG"
fi

# ---- 3b) Appcast do Sparkle (so se o pacote + chaves existirem) -----------
# Se o Sparkle ja foi adicionado ao projeto (SETUP_SPARKLE.md), gera e assina o
# appcast.xml apontando o download para o asset do release. Sem Sparkle, pula
# sem abortar (a atualizacao automatica fica inativa ate concluir o setup).
GEN="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/artifacts/sparkle/Sparkle/bin/generate_appcast' 2>/dev/null | head -1 || true)"
if [ -n "$GEN" ]; then
  echo "Gerando/assinando o appcast (Sparkle)..."
  ACDIR="$WORK/appcast"; mkdir -p "$ACDIR"
  cp "$OUT_DMG" "$ACDIR/"
  [ -f appcast.xml ] && cp appcast.xml "$ACDIR/appcast.xml"
  if "$GEN" "$ACDIR" --download-url-prefix "https://github.com/$OWNER/$REPO/releases/download/$TAG/"; then
    cp "$ACDIR/appcast.xml" appcast.xml
    echo "appcast.xml atualizado (sera commitado e enviado abaixo)."
  else
    echo "Aviso: generate_appcast falhou (gerou as chaves EdDSA? veja SETUP_SPARKLE.md). Seguindo sem appcast."
  fi
else
  echo "Sparkle ainda nao instalado - pulando o appcast (auto-update fica inativo ate o setup; veja SETUP_SPARKLE.md)."
fi

# ---- 4) Commit + sincroniza + push ----------------------------------------
if [ -n "$(git status --porcelain)" ]; then
  echo "Commitando mudancas pendentes..."
  git add -A
  git commit -q -m "$TAG"
fi
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
echo "Sincronizando com o remoto (pull --rebase)..."
if ! git pull --rebase --autostash origin "$BRANCH"; then
  echo "Conflito ao integrar mudancas do remoto. Resolva e rode de novo: ./release.sh --no-build"
  exit 1
fi
echo "git push..."
git push -q origin "$BRANCH"

# ---- 5) Tag vX.Y.Z ---------------------------------------------------------
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG ja existe."
else
  echo "Criando e empurrando a tag $TAG..."
  git tag -a "$TAG" -m "Lume $TAG"
  git push -q origin "$TAG"
fi

# ---- 6) Notas: so a secao da versao atual (antes do historico <details>) ---
NOTES="$WORK/notes.md"
if [ -f RELEASE_NOTES.md ]; then
  awk 'BEGIN{p=1} /^<details>/{p=0} p {print}' RELEASE_NOTES.md > "$NOTES"
else
  echo "Lume $TAG" > "$NOTES"
fi
if [ "$DRAFT" = "1" ]; then LATEST=0; else LATEST=1; fi

# ---- 6a) Caminho rapido: gh, se instalado e autenticado --------------------
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "Publicando via GitHub CLI (gh)..."
  if [ "$DRAFT" = "1" ]; then FLAG=(--draft); else FLAG=(--latest); fi
  if gh release view "$TAG" >/dev/null 2>&1; then
    gh release edit   "$TAG" --notes-file "$NOTES" "${FLAG[@]}"
    gh release upload "$TAG" "$OUT_DMG" --clobber
  else
    gh release create "$TAG" "$OUT_DMG" --title "Lume $TAG" --notes-file "$NOTES" "${FLAG[@]}"
  fi
  echo "Publicado: $(gh release view "$TAG" --json url -q .url)"
  exit 0
fi

# ---- 6b) Sem gh: API do GitHub via python3 + token -------------------------
TOKEN="${GITHUB_TOKEN:-}"
[ -n "$TOKEN" ] || TOKEN="$(security find-generic-password -s "$KC_SERVICE" -w 2>/dev/null || true)"
if [ -z "$TOKEN" ]; then
  printf "Personal Access Token do GitHub (escopo repo): "
  read -rs TOKEN; echo
  if [ -n "$TOKEN" ]; then
    security add-generic-password -U -a "$USER" -s "$KC_SERVICE" -w "$TOKEN" 2>/dev/null \
      && echo "Token salvo no Keychain — nas proximas vezes nao vai pedir."
  fi
fi
[ -n "$TOKEN" ] || { echo "Token vazio."; exit 1; }

GH_TOKEN="$TOKEN" python3 - "$OWNER" "$REPO" "$TAG" "$NOTES" "$LATEST" "$OUT_DMG" <<'PY'
import os, sys, json, urllib.request, urllib.error
tok = os.environ["GH_TOKEN"]
owner, repo, tag, notes_path, latest, *assets = sys.argv[1:]
API = "https://api.github.com"
def req(method, url, data=None, ctype=None):
    h = {"Authorization": f"Bearer {tok}", "Accept": "application/vnd.github+json",
         "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "Lume-Release"}
    if ctype: h["Content-Type"] = ctype
    r = urllib.request.Request(url, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(r) as resp: return resp.status, resp.read()
    except urllib.error.HTTPError as e: return e.code, e.read()

notes = open(notes_path, encoding="utf-8").read()
mklatest = "true" if latest == "1" else "false"

st, body = req("GET", f"{API}/repos/{owner}/{repo}/releases/tags/{tag}")
if st == 200:
    rel = json.loads(body); rid = rel["id"]
    req("PATCH", f"{API}/repos/{owner}/{repo}/releases/{rid}", ctype="application/json",
        data=json.dumps({"name": f"Lume {tag}", "body": notes,
                         "draft": latest == "0", "make_latest": mklatest}).encode())
else:
    st2, b2 = req("POST", f"{API}/repos/{owner}/{repo}/releases", ctype="application/json",
        data=json.dumps({"tag_name": tag, "name": f"Lume {tag}", "body": notes,
                         "draft": latest == "0", "make_latest": mklatest}).encode())
    if st2 not in (200, 201):
        print("erro ao criar release:", st2, b2.decode()[:400]); sys.exit(1)
    rel = json.loads(b2); rid = rel["id"]

st, b = req("GET", f"{API}/repos/{owner}/{repo}/releases/{rid}/assets")
existing = {a["name"]: a["id"] for a in (json.loads(b) if st == 200 else [])}
for path in assets:
    if not path or not os.path.isfile(path): continue
    name = os.path.basename(path)
    if name in existing:
        req("DELETE", f"{API}/repos/{owner}/{repo}/releases/assets/{existing[name]}")
    with open(path, "rb") as f: blob = f.read()
    st, b = req("POST",
                f"https://uploads.github.com/repos/{owner}/{repo}/releases/{rid}/assets?name={name}",
                data=blob, ctype="application/octet-stream")
    if st not in (200, 201):
        print(f"erro no upload de {name}:", st, b.decode()[:300]); sys.exit(1)
    print(" anexado:", name)

print("Publicado:", rel["html_url"])
PY
