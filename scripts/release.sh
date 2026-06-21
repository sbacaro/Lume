#!/usr/bin/env bash
#
# release.sh — Release do Lume.
#
# Dois modos:
#   • Apenas push      — commit + sincroniza + push das mudanças (sem build/release).
#   • Release completo — versão, build, DMG, appcast assinado, tag e release no GitHub.
#
# Sem flag de modo, o script PERGUNTA qual você quer. Passar uma versão (ex.: 1.5.1)
# assume release completo automaticamente.
#
# Autocontido: NAO depende de outros scripts. Sem Homebrew nem gh obrigatorios
# (usa git + python3 do macOS). Se o gh estiver instalado e autenticado, usa ele.
#
# Uso:
#   ./scripts/release.sh                 # pergunta: apenas push ou release completo
#   ./scripts/release.sh --push          # apenas push (commit + push)
#   ./scripts/release.sh --full          # release completo (versao atual)
#   ./scripts/release.sh 1.3.4           # release completo definindo nova versao
#   ./scripts/release.sh 1.4.0 9         # release completo com versao e build explicitos
#   ./scripts/release.sh --no-build      # release reaproveitando o DMG ja gerado
#   ./scripts/release.sh --draft         # release como rascunho (nao vira latest)
#   ./scripts/release.sh --save-token    # salva/atualiza o token do GitHub no Keychain e sai
#   ./scripts/release.sh --forget-token  # remove o token do Keychain
#
# Observacao: nao usamos `set -u` de proposito. O arquivo fica num Drive
# sincronizado e variaveis sempre definidas (TAG, VERSION...) nao precisam de
# nounset; evita abortos espurios de "unbound variable".
set -eo pipefail
# script vive em scripts/ — opera a partir da raiz do repo
cd "$(dirname "$0")/.."

# ---- UI: cores e helpers de status -----------------------------------------
BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; BLU=""; CYA=""; RST=""
if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
  if [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    BOLD="$(tput bold)"; DIM="$(tput dim)"; RST="$(tput sgr0)"
    RED="$(tput setaf 1)"; GRN="$(tput setaf 2)"; YLW="$(tput setaf 3)"
    BLU="$(tput setaf 4)"; CYA="$(tput setaf 6)"
  fi
fi
hr()    { printf "${DIM}────────────────────────────────────────────${RST}\n"; }
say()   { printf "%s\n" "$*"; }
step()  { printf "${BLU}▸${RST} %s\n" "$*"; }
ok()    { printf "${GRN}✓${RST} %s\n" "$*"; }
warn()  { printf "${YLW}!${RST} %s\n" "$*"; }
die()   { printf "${RED}✗ %s${RST}\n" "$*" >&2; exit 1; }
banner(){ printf "\n${BOLD}${CYA}  Lume${RST}${BOLD} · %s${RST}\n" "$1"; hr; }

[ "$(uname)" = "Darwin" ] || die "Rode no macOS."

# Área de trabalho temporária (logs de build, appcast, DMG nativo).
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

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
NO_BUILD=0; DRAFT=0; NEW_VER=""; NEW_BUILD=""; MODE=""
for a in "$@"; do
  case "$a" in
    --push|--push-only) MODE="push" ;;
    --full)     MODE="full" ;;
    --no-build) NO_BUILD=1 ;;
    --draft)    DRAFT=1 ;;
    --save-token)
        printf "Cole o token do GitHub (escopo repo): "; read -rs _T; echo
        [ -n "$_T" ] && security add-generic-password -U -a "$USER" -s "$KC_SERVICE" -w "$_T" \
          && ok "Token salvo no Keychain." || warn "Nada salvo."; exit 0 ;;
    --forget-token)
        security delete-generic-password -s "$KC_SERVICE" >/dev/null 2>&1 \
          && ok "Token removido." || warn "Nenhum token salvo."; exit 0 ;;
    [0-9]*.[0-9]*) if [ -z "$NEW_VER" ]; then NEW_VER="$a"; else NEW_BUILD="$a"; fi ;;
    [0-9]*)        NEW_BUILD="$a" ;;
    *) die "Argumento desconhecido: $a" ;;
  esac
done

# Passar uma versão implica release completo.
[ -n "$NEW_VER" ] && MODE="full"

# ---- git helper compartilhado ----------------------------------------------
git_commit_sync_push() {  # $1 = mensagem de commit
  local msg="$1" branch
  if [ -n "$(git status --porcelain)" ]; then
    step "Commitando mudanças…"
    git add -A
    git commit -q -m "$msg"
    ok "Commit: ${DIM}$msg${RST}"
  else
    say "  ${DIM}nada pendente para commitar${RST}"
  fi
  branch="$(git rev-parse --abbrev-ref HEAD)"
  step "Sincronizando com o remoto (rebase)…"
  git pull --rebase --autostash -q origin "$branch" \
    || die "Conflito no rebase. Resolva e rode de novo: ./scripts/release.sh --no-build"
  step "Enviando para origin/$branch…"
  git push -q origin "$branch"
  ok "Push concluído em ${BOLD}origin/$branch${RST}"
}

# ---- Pergunta o modo, se não foi definido ----------------------------------
if [ -z "$MODE" ]; then
  if [ -t 0 ]; then
    banner "Release"
    say "  ${BOLD}1${RST}) Apenas push        ${DIM}commit + push das mudanças${RST}"
    say "  ${BOLD}2${RST}) Release completo   ${DIM}build · DMG · appcast · tag · GitHub${RST}"
    printf "\nEscolha [${BOLD}1${RST}/2]: "
    read -r _c
    case "$_c" in
      2|f|full|completo) MODE="full" ;;
      *)                 MODE="push" ;;
    esac
  else
    MODE="full"   # não-interativo sem flag: mantém o comportamento antigo
  fi
fi

# ---- Modo: apenas push -----------------------------------------------------
if [ "$MODE" = "push" ]; then
  banner "Apenas push"
  DEF_MSG="chore: update ($(date +%Y-%m-%d))"
  if [ -t 0 ]; then
    printf "Mensagem do commit ${DIM}(enter = \"%s\")${RST}: " "$DEF_MSG"
    read -r _m; [ -n "$_m" ] && DEF_MSG="$_m"
  fi
  git_commit_sync_push "$DEF_MSG"
  printf "\n${GRN}${BOLD}Pronto.${RST}\n"
  exit 0
fi

# ============================================================================
#  Modo: RELEASE COMPLETO
# ============================================================================
[ -f "$CFG" ] || die "$CFG nao encontrado."
read_kv() { grep -E "^$1" "$CFG" | sed -E 's/.*= *//' | tr -d ' '; }

# ---- 1) Versao (FONTE UNICA) ----------------------------------------------
if [ -n "$NEW_VER" ]; then
  case "$NEW_VER" in
    [0-9]*.[0-9]*) : ;;
    *) die "Versao invalida: '$NEW_VER'" ;;
  esac
  CUR_BUILD="$(read_kv CURRENT_PROJECT_VERSION)"
  [ -n "$NEW_BUILD" ] || NEW_BUILD=$(( ${CUR_BUILD:-0} + 1 ))
  sed -i '' -E "s/^MARKETING_VERSION = .*/MARKETING_VERSION = ${NEW_VER}/"               "$CFG"
  sed -i '' -E "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = ${NEW_BUILD}/" "$CFG"
fi

VERSION="$(read_kv MARKETING_VERSION)"
BUILD="$(read_kv CURRENT_PROJECT_VERSION)"
[ -n "$VERSION" ] || die "Nao consegui ler a versao de $CFG."
TAG="v$VERSION"
OUT_DMG="$PWD/${APP_NAME}-${VERSION}.dmg"
APP="$BUILD_DIR/Build/Products/$CONFIG/$APP_NAME.app"
# PKG descontinuado: o app vai DENTRO do DMG. Remove .pkg antigo desta versao.
rm -f "$PWD/${APP_NAME}-${VERSION}.pkg"

REMOTE="$(git remote get-url origin 2>/dev/null || echo "")"
SLUG="$(echo "$REMOTE" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
[ -n "$SLUG" ] || SLUG="sbacaro/Lume"
OWNER="${SLUG%%/*}"; REPO="${SLUG##*/}"

banner "Release completo"
say "  ${DIM}repo${RST}  ${BOLD}$OWNER/$REPO${RST}"
say "  ${DIM}versão${RST} ${BOLD}$VERSION${RST} ${DIM}(build $BUILD)${RST}   ${DIM}tag${RST} ${BOLD}$TAG${RST}"
hr

# ---- 2) Compilar o app -----------------------------------------------------
if [ "$NO_BUILD" = "1" ] && [ -d "$APP" ]; then
  ok "Reaproveitando app já compilado"
else
  command -v xcodebuild >/dev/null || die "xcodebuild nao encontrado (instale o Xcode)."
  step "Compilando ($CONFIG) — pode levar alguns minutos…"
  rm -rf "$BUILD_DIR"
  if command -v xcbeautify >/dev/null 2>&1; then
    xcodebuild \
      -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
      -derivedDataPath "$BUILD_DIR" -destination 'generic/platform=macOS' \
      clean build \
      CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
      2>&1 | xcbeautify --quiet || die "Falha na compilação."
  else
    # Sem xcbeautify: build silencioso, log só aparece se falhar.
    if ! xcodebuild \
        -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
        -derivedDataPath "$BUILD_DIR" -destination 'generic/platform=macOS' \
        clean build \
        CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
        > "$WORK/build.log" 2>&1; then
      tail -n 40 "$WORK/build.log" >&2
      die "Falha na compilação (log completo: $WORK/build.log)."
    fi
  fi
  [ -d "$APP" ] || die ".app nao encontrado em: $APP"
  ok "App compilado"
fi

# ---- 3) DMG (com o Lume.app dentro) ----------------------------------------
if [ "$NO_BUILD" = "1" ] && [ -f "$OUT_DMG" ]; then
  ok "Reaproveitando DMG já gerado"
else
  rm -f "$OUT_DMG"
  BG_PNG="$WORK/background.png"
  step "Montando o DMG (fundo da marca + atalho do Applications)…"
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
    "$DMGBUILD" -s "$WORK/settings.py" "$VOL_NAME" "$OUT_DMG" >/dev/null
  else
    warn "dmgbuild indisponível — usando método nativo (hdiutil + Finder)…"
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
  ok "DMG pronto ${DIM}($(du -h "$OUT_DMG" | cut -f1), Lume.app dentro)${RST}"
fi

# ---- 3b) Appcast do Sparkle (assinado em EdDSA) ---------------------------
# O app exige updates ASSINADOS quando SUPublicEDKey esta no projeto. Geramos o
# appcast.xml (estrutura/historico) e GARANTIMOS a `sparkle:edSignature` desta
# versao via `sign_update` — injetada direto no enclosure. Nao confiamos no
# generate_appcast pra (re)assinar: quando a entrada ja existe no appcast antigo,
# ele so atualiza metadados e PRESERVA o estado sem assinatura, gerando o erro
# "improperly signed and could not be validated" no Sparkle.
REQUIRES_SIG=0
grep -Eq 'INFOPLIST_KEY_SUPublicEDKey = "[^"]+"' "$PROJECT/project.pbxproj" 2>/dev/null && REQUIRES_SIG=1
DMG_NAME="$(basename "$OUT_DMG")"
DL_PREFIX="https://github.com/$OWNER/$REPO/releases/download/$TAG/"

# Acha as ferramentas do Sparkle onde quer que ele as tenha colocado.
find_tool() {
  local t; t="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
                     "$HOME/Library/Caches/org.sparkle-project.Sparkle" \
                     -name "$1" -type f 2>/dev/null | head -1 || true)"
  [ -n "$t" ] || t="$(command -v "$1" 2>/dev/null || true)"
  printf '%s' "$t"
}
GEN="$(find_tool generate_appcast)"
SIGN="$(find_tool sign_update)"

appcast_signed() {  # 1 se o enclosure de $DMG_NAME tem edSignature nao-vazia
  [ -f appcast.xml ] || return 1
  grep -F "$DMG_NAME" appcast.xml | grep -q 'sparkle:edSignature="[^"]\{20,\}"'
}

if [ -n "$GEN" ]; then
  step "Gerando o appcast (Sparkle)…"
  ACDIR="$WORK/appcast"; mkdir -p "$ACDIR"
  cp "$OUT_DMG" "$ACDIR/"
  [ -f appcast.xml ] && cp appcast.xml "$ACDIR/appcast.xml"
  "$GEN" "$ACDIR" --download-url-prefix "$DL_PREFIX" >/dev/null 2>&1 || \
    warn "generate_appcast retornou erro; sigo e tento assinar manualmente."
  [ -f "$ACDIR/appcast.xml" ] && cp "$ACDIR/appcast.xml" appcast.xml
fi

# Garante a assinatura desta versao (mesmo que o generate_appcast nao tenha posto).
if ! appcast_signed && [ -n "$SIGN" ] && [ -f appcast.xml ]; then
  step "Assinando $DMG_NAME (EdDSA) e injetando no appcast…"
  SIG_LINE="$("$SIGN" "$OUT_DMG" 2>/dev/null || true)"   # ex.: sparkle:edSignature="..." length="..."
  ED_SIG="$(printf '%s' "$SIG_LINE" | sed -n 's/.*edSignature="\([^"]*\)".*/\1/p')"
  if [ -n "$ED_SIG" ]; then
    LEN="$(printf '%s' "$SIG_LINE" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"
    [ -n "$LEN" ] || LEN="$(stat -f%z "$OUT_DMG" 2>/dev/null || wc -c <"$OUT_DMG")"
    DMG_NAME="$DMG_NAME" ED_SIG="$ED_SIG" LEN="$LEN" python3 - appcast.xml <<'PY'
import os, re, sys
path = sys.argv[1]
name, sig, length = os.environ["DMG_NAME"], os.environ["ED_SIG"], os.environ["LEN"]
xml = open(path, encoding="utf-8").read()
# Acha o enclosure cujo url termina com o nome do DMG e reescreve seus atributos,
# preservando edSignature unica e length correto.
def fix(m):
    tag = m.group(0)
    if name not in tag:
        return tag
    tag = re.sub(r'\s+sparkle:edSignature="[^"]*"', "", tag)
    tag = re.sub(r'\s+length="[^"]*"', "", tag)
    tag = tag.replace("<enclosure ", f'<enclosure length="{length}" sparkle:edSignature="{sig}" ', 1)
    return tag
new = re.sub(r"<enclosure\b[^>]*/>", fix, xml)
if new == xml:
    sys.exit("nao encontrei o enclosure de " + name)
open(path, "w", encoding="utf-8").write(new)
PY
  else
    warn "sign_update nao retornou edSignature."
  fi
fi

# Veredito final: se o app exige assinatura, ela TEM que estar la.
if appcast_signed; then
  ok "appcast.xml assinado ${DIM}(edSignature presente para $DMG_NAME)${RST}"
elif [ "$REQUIRES_SIG" = "1" ]; then
  printf "${RED}✗ O app exige updates assinados (SUPublicEDKey definido) mas não consegui${RST}\n" >&2
  printf "${RED}  assinar %s. Compile o Sparkle (Cmd+B no Xcode, gera generate_appcast/${RST}\n" "$DMG_NAME" >&2
  printf "${RED}  sign_update em DerivedData) e confirme a chave EdDSA no Keychain${RST}\n" >&2
  die "(./scripts/setup-sparkle.sh). NAO vou publicar sem assinatura."
else
  warn "Sparkle ainda não instalado — pulando o appcast (auto-update inativo até o setup; veja docs/SPARKLE_SETUP.md)."
fi

# ---- 4) Commit + sincroniza + push ----------------------------------------
git_commit_sync_push "$TAG"

# ---- 5) Tag vX.Y.Z ---------------------------------------------------------
if git rev-parse "$TAG" >/dev/null 2>&1; then
  ok "Tag $TAG já existe"
else
  step "Criando e empurrando a tag $TAG…"
  git tag -a "$TAG" -m "Lume $TAG"
  git push -q origin "$TAG"
  ok "Tag $TAG publicada"
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
  step "Publicando via GitHub CLI (gh)…"
  if [ "$DRAFT" = "1" ]; then FLAG=(--draft); else FLAG=(--latest); fi
  if gh release view "$TAG" >/dev/null 2>&1; then
    gh release edit   "$TAG" --notes-file "$NOTES" "${FLAG[@]}" >/dev/null
    gh release upload "$TAG" "$OUT_DMG" --clobber >/dev/null
  else
    gh release create "$TAG" "$OUT_DMG" --title "Lume $TAG" --notes-file "$NOTES" "${FLAG[@]}" >/dev/null
  fi
  printf "\n${GRN}${BOLD}Publicado.${RST}  %s\n" "$(gh release view "$TAG" --json url -q .url)"
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
      && ok "Token salvo no Keychain — nas próximas vezes não vai pedir."
  fi
fi
[ -n "$TOKEN" ] || die "Token vazio."

step "Publicando via API do GitHub…"
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
    print("  anexado:", name)

print("Publicado:", rel["html_url"])
PY
