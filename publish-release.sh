#!/usr/bin/env bash
#
# publish-release.sh — Publica o release do Lume no GitHub pelo terminal
#
# Não precisa de Homebrew nem do gh: usa o que já vem no macOS (git + python3)
# via API do GitHub. Se o gh estiver instalado e autenticado, usa ele.
#
#   1) Lê a versão da FONTE ÚNICA (Version.xcconfig)
#   2) Garante o .dmg (compila com build-release.sh se não existir)
#   3) Commita/pusha o que estiver pendente
#   4) Cria/atualiza o release vX.Y.Z, anexa o .dmg e marca como "latest"
#
# Token (caminho sem gh): um Personal Access Token com escopo `repo`.
#   Crie em: https://github.com/settings/tokens  (classic, escopo repo)
#   O token é pedido UMA vez e guardado no Keychain do macOS — depois o script
#   lê de lá sozinho, sem perguntar de novo. Ordem: $GITHUB_TOKEN → Keychain → pergunta.
#
# Uso:
#   ./publish-release.sh              # build (se preciso) + publica
#   ./publish-release.sh --no-build   # usa o .dmg já existente
#   ./publish-release.sh --draft      # cria como rascunho (não fica latest)
#   ./publish-release.sh --save-token # salva/atualiza o token no Keychain e sai
#   ./publish-release.sh --forget-token # remove o token do Keychain
#
set -euo pipefail
cd "$(dirname "$0")"
[[ "$(uname)" == "Darwin" ]] || { echo "✖ Rode no macOS."; exit 1; }

KC_SERVICE="lume-github-token"   # onde o token fica guardado no Keychain
NO_BUILD=0; DRAFT=0
for a in "$@"; do
  case "$a" in
    --no-build) NO_BUILD=1 ;;
    --draft)    DRAFT=1 ;;
    --save-token)
        printf "🔑 Cole o token (escopo repo): "; read -rs _T; echo
        [[ -n "$_T" ]] && security add-generic-password -U -a "$USER" -s "$KC_SERVICE" -w "$_T" \
          && echo "✔ Token salvo no Keychain (serviço: $KC_SERVICE)." || echo "✖ Nada salvo."
        exit 0 ;;
    --forget-token)
        security delete-generic-password -s "$KC_SERVICE" >/dev/null 2>&1 \
          && echo "✔ Token removido do Keychain." || echo "Nenhum token salvo."
        exit 0 ;;
  esac
done

VERSION="$(grep -E '^MARKETING_VERSION' Version.xcconfig | sed -E 's/.*= *//' | tr -d ' ')"
[[ -n "$VERSION" ]] || { echo "✖ Não consegui ler a versão de Version.xcconfig."; exit 1; }
TAG="v$VERSION"
DMG="$PWD/Lume-$VERSION.dmg"

# OWNER/REPO a partir do remoto git
REMOTE="$(git remote get-url origin 2>/dev/null || echo "")"
SLUG="$(echo "$REMOTE" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
[[ -n "$SLUG" ]] || SLUG="sbacaro/Lume"
OWNER="${SLUG%%/*}"; REPO="${SLUG##*/}"
echo "▶ Repo: $OWNER/$REPO   Versão: $VERSION   Tag: $TAG"

# ── 1/2) Garante o .dmg ──────────────────────────────────────────────────────
if [[ ! -f "$DMG" ]]; then
  [[ "$NO_BUILD" == "1" ]] && { echo "✖ $DMG não existe (e --no-build foi passado)."; exit 1; }
  echo "▶ DMG não encontrado — compilando…"; ./build-release.sh
fi
[[ -f "$DMG" ]] || { echo "✖ $DMG não foi gerado."; exit 1; }
echo "✔ DMG: $DMG ($(du -h "$DMG" | cut -f1))"

# ── 3) Commit/push do que estiver pendente ───────────────────────────────────
if [[ -n "$(git status --porcelain)" ]]; then
  echo "▶ Commitando mudanças pendentes…"; git add -A; git commit -m "$TAG"
fi
echo "▶ git push…"; git push

# ── 4) Notas: só a seção da versão atual (antes do histórico <details>) ───────
NOTES="$(mktemp)"; trap 'rm -f "$NOTES"' EXIT
awk 'BEGIN{p=1} /^<details>/{p=0} p {print}' RELEASE_NOTES.md > "$NOTES"
LATEST=$([[ "$DRAFT" == "1" ]] && echo 0 || echo 1)

# ── 5a) Caminho rápido: gh, se instalado e autenticado ───────────────────────
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "▶ Usando GitHub CLI (gh)…"
  FLAG=(--latest); [[ "$DRAFT" == "1" ]] && FLAG=(--draft)
  if gh release view "$TAG" >/dev/null 2>&1; then
    gh release edit   "$TAG" --notes-file "$NOTES" "${FLAG[@]}"
    gh release upload "$TAG" "$DMG" --clobber
  else
    gh release create "$TAG" "$DMG" --title "Lume $TAG" --notes-file "$NOTES" "${FLAG[@]}"
  fi
  echo "✅ Publicado: $(gh release view "$TAG" --json url -q .url)"
  exit 0
fi

# ── 5b) Sem gh: API do GitHub via python3 + token ────────────────────────────
# token: env  →  Keychain  →  pergunta (e salva no Keychain na 1ª vez)
TOKEN="${GITHUB_TOKEN:-}"
[[ -z "$TOKEN" ]] && TOKEN="$(security find-generic-password -s "$KC_SERVICE" -w 2>/dev/null || true)"
if [[ -z "$TOKEN" ]]; then
  printf "🔑 Personal Access Token (escopo repo): "
  read -rs TOKEN; echo
  if [[ -n "$TOKEN" ]]; then
    security add-generic-password -U -a "$USER" -s "$KC_SERVICE" -w "$TOKEN" 2>/dev/null \
      && echo "✔ Token salvo no Keychain — nas próximas vezes não vai pedir."
  fi
fi
[[ -n "$TOKEN" ]] || { echo "✖ Token vazio."; exit 1; }

GH_TOKEN="$TOKEN" python3 - "$OWNER" "$REPO" "$TAG" "$DMG" "$NOTES" "$LATEST" <<'PY'
import os, sys, json, urllib.request, urllib.error
tok, owner, repo, tag, dmg, notes_path, latest = os.environ["GH_TOKEN"], *sys.argv[1:7]
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
        print("✖ erro ao criar release:", st2, b2.decode()[:400]); sys.exit(1)
    rel = json.loads(b2); rid = rel["id"]

name = os.path.basename(dmg)
st, b = req("GET", f"{API}/repos/{owner}/{repo}/releases/{rid}/assets")
for a in (json.loads(b) if st == 200 else []):
    if a["name"] == name:
        req("DELETE", f"{API}/repos/{owner}/{repo}/releases/assets/{a['id']}")

with open(dmg, "rb") as f: blob = f.read()
st, b = req("POST",
            f"https://uploads.github.com/repos/{owner}/{repo}/releases/{rid}/assets?name={name}",
            data=blob, ctype="application/octet-stream")
if st not in (200, 201):
    print("✖ erro no upload do .dmg:", st, b.decode()[:400]); sys.exit(1)
print("✅ Publicado:", rel["html_url"])
PY
