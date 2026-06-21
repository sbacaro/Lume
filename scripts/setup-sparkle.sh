#!/usr/bin/env bash
#
# setup-sparkle.sh — Configura o auto-update (Sparkle) de ponta a ponta, em tudo
# que da pra automatizar:
#
#   1) Confere se o pacote Sparkle esta no projeto (a unica etapa manual)
#   2) Resolve o pacote e compila pra extrair as ferramentas do Sparkle
#   3) Gera as chaves EdDSA (privada no Keychain) e le a chave publica
#   4) Injeta a chave publica no projeto (SUPublicEDKey, Debug + Release)
#
# Depois disso, `./scripts/release.sh 1.3.4` ja publica com o appcast assinado.
#
# A UNICA coisa que este script NAO faz e adicionar o pacote Sparkle ao Xcode:
# a Apple nao tem um comando de terminal confiavel pra isso. Se faltar, o script
# te mostra exatamente o que clicar (leva ~20s) e pede pra rodar de novo.
#
# Uso: ./scripts/setup-sparkle.sh
#
# (sem `set -u` de proposito; o arquivo vive num Drive sincronizado e nao
#  precisamos de nounset — evita abortos espurios.)
set -eo pipefail
# script vive em scripts/ — opera a partir da raiz do repo
cd "$(dirname "$0")/.."
[ "$(uname)" = "Darwin" ] || { echo "Rode no macOS."; exit 1; }

PROJECT="Lume.xcodeproj"
PBX="$PROJECT/project.pbxproj"
SCHEME="Lume"
DERIVED="$HOME/Library/Developer/Xcode/DerivedData"

command -v xcodebuild >/dev/null || { echo "xcodebuild nao encontrado (instale o Xcode)."; exit 1; }
[ -f "$PBX" ] || { echo "$PBX nao encontrado. Rode na raiz do projeto."; exit 1; }

# Garante que o passo 4 (chaves no Info.plist) ja esta no projeto
if ! grep -q "INFOPLIST_KEY_SUPublicEDKey" "$PBX"; then
  echo "Nao encontrei INFOPLIST_KEY_SUPublicEDKey no projeto."
  echo "Rode o passo 4 (build settings do Sparkle) antes — ou peca pro Claude refazer."
  exit 1
fi

# ---- 1) O pacote Sparkle esta no projeto? ---------------------------------
if ! grep -q "sparkle-project/Sparkle" "$PBX"; then
  cat <<'MSG'
======================================================================
 Falta 1 passo manual (~20s) no Xcode. Depois rode este script de novo:

   Xcode  >  File  >  Add Package Dependencies...
     URL:      https://github.com/sparkle-project/Sparkle
     Versao:   Up to Next Major, a partir de 2.6.0
     Target:   adicione o produto "Sparkle" ao target "Lume"

 (A Apple nao tem um comando de terminal confiavel pra adicionar pacotes
  SPM a um .xcodeproj; por isso essa etapa fica no Xcode. O resto eu faco.)
======================================================================
MSG
  exit 1
fi
echo "[1/4] Pacote Sparkle: presente no projeto."

# ---- 2) Resolve o pacote e compila pra extrair as ferramentas -------------
echo "[2/4] Resolvendo o pacote e compilando (pode demorar um pouco)..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -resolvePackageDependencies >/dev/null
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=macOS' build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
  >/dev/null 2>&1 || true

# ---- 3) Chaves EdDSA: garante a privada (Keychain) e le a publica ---------
KEYS="$(find "$DERIVED" -path '*/artifacts/sparkle/Sparkle/bin/generate_keys' 2>/dev/null | head -1 || true)"
if [ -z "$KEYS" ]; then
  echo "Nao achei o 'generate_keys' do Sparkle."
  echo "Abra o projeto no Xcode, faca um build (Cmd+B) uma vez e rode este script de novo."
  exit 1
fi
echo "[3/4] Gerando/lendo as chaves EdDSA..."
"$KEYS" >/dev/null 2>&1 || true                 # cria a chave se ainda nao existir
PUBKEY="$("$KEYS" -p 2>/dev/null || true)"      # imprime a chave publica da existente
if [ -z "$PUBKEY" ]; then
  PUBKEY="$("$KEYS" 2>&1 | grep -oE '[A-Za-z0-9+/]{40,}={0,2}' | head -1 || true)"
fi
PUBKEY="$(printf '%s' "$PUBKEY" | tr -d '[:space:]')"
case "$PUBKEY" in
  "" | *[!A-Za-z0-9+/=]*)
    echo "Nao consegui obter uma chave publica valida do Sparkle."; exit 1 ;;
esac

# ---- 4) Injeta a chave publica no projeto (Debug + Release) ---------------
cp "$PBX" "$PBX.bak"
sed -i '' -E "s|INFOPLIST_KEY_SUPublicEDKey = \"[^\"]*\";|INFOPLIST_KEY_SUPublicEDKey = \"${PUBKEY}\";|g" "$PBX"
if grep -q "INFOPLIST_KEY_SUPublicEDKey = \"${PUBKEY}\";" "$PBX"; then
  rm -f "$PBX.bak"
  echo "[4/4] Chave publica injetada no projeto (Debug + Release)."
else
  mv "$PBX.bak" "$PBX"
  echo "Nao consegui substituir a chave no projeto; restaurei o pbxproj sem mudancas."
  exit 1
fi

cat <<MSG

Sparkle configurado:
  - chave privada -> no seu Keychain (NAO compartilhe, nao da pra recuperar)
  - chave publica -> no projeto (SUPublicEDKey)
  - SUFeedURL     -> https://raw.githubusercontent.com/sbacaro/Lume/main/appcast.xml

Agora e so publicar (compila, ASSINA o appcast e sobe tudo):

  ./scripts/release.sh 1.3.4

Observacao: o PRIMEIRO build com Sparkle precisa ser instalado a mao uma vez
(a 1.3.2/1.3.3 nao tem Sparkle pra se auto-atualizar). Da 1.3.4 em diante, o
app se atualiza sozinho, sem navegador.
MSG
