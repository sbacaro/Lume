# Atualização automática com Sparkle — Setup

O código já está integrado (`Lume/SparkleUpdater.swift`, menu **Verificar Atualizações…**,
botão **Check** no About). Enquanto o pacote Sparkle **não** estiver adicionado, o app
compila normalmente e o botão só abre a página de releases (fallback). Depois de seguir
os passos abaixo, o app passa a **baixar o `.dmg`, instalar e reiniciar sozinho** — na
próxima abertura já está na versão nova.

> O app é distribuído **sem assinatura da Apple**, então a segurança da atualização vem
> da **assinatura EdDSA** do Sparkle (obrigatória nesse caso). É o que os passos 2 e 5 cobrem.

---

## 1. Adicionar o pacote Sparkle (Xcode, ~30s)

1. No Xcode: **File → Add Package Dependencies…**
2. URL: `https://github.com/sparkle-project/Sparkle`
3. Regra de versão: **Up to Next Major** a partir de `2.6.0`.
4. Adicione o produto **Sparkle** ao target **Lume**.

Pronto — como o código usa `#if canImport(Sparkle)`, o updater real é ativado
automaticamente assim que o pacote existe.

---

## 2. Gerar as chaves de assinatura (uma única vez)

As ferramentas vêm dentro do pacote. Depois do passo 1, rode:

```bash
# Localiza o binário dentro do DerivedData (ou use ./generate-appcast.sh que faz isso por você)
BIN="$(find ~/Library/Developer/Xcode/DerivedData -path '*/artifacts/sparkle/Sparkle/bin/generate_keys' 2>/dev/null | head -1)"
"$BIN"
```

- A **chave privada** é guardada no **Keychain** do seu Mac (não compartilhe).
- Ele imprime a **chave pública** (uma linha base64). Copie-a para o passo 3 (`SUPublicEDKey`).

---

## 3. Configurar o Info.plist

O projeto usa `GENERATE_INFOPLIST_FILE = YES`. Adicione as chaves customizadas pelo
**target Lume → aba Info** (ou em **Build Settings**, como `INFOPLIST_KEY_<chave>`):

| Chave | Valor |
|---|---|
| `SUFeedURL` | `https://raw.githubusercontent.com/sbacaro/Lume/main/appcast.xml` |
| `SUPublicEDKey` | *(a chave pública do passo 2)* |
| `SUEnableAutomaticChecks` | `YES` |
| `SUScheduledCheckInterval` | `86400` *(opcional — 1×/dia)* |

Equivalente em Build Settings:

```
INFOPLIST_KEY_SUFeedURL = https://raw.githubusercontent.com/sbacaro/Lume/main/appcast.xml
INFOPLIST_KEY_SUPublicEDKey = <chave pública>
INFOPLIST_KEY_SUEnableAutomaticChecks = YES
INFOPLIST_KEY_SUScheduledCheckInterval = 86400
```

---

## 4. Fluxo de cada release

```bash
# 1) Build no Xcode (Product → Archive ou ⌘B)
# 2) Gera o .dmg (já existente)
./build-dmg.sh                       # -> Lume-1.2.0.dmg

# 3) Gera/atualiza e ASSINA o appcast (usa a chave privada do Keychain)
./generate-appcast.sh Lume-1.2.0.dmg v1.2.0
#    -> escreve/atualiza appcast.xml na raiz do repo
```

`generate-appcast.sh` (incluído) localiza o `generate_appcast` do Sparkle, lê a versão
de dentro do `.dmg`, calcula a assinatura EdDSA e monta o `appcast.xml` apontando o
download para o asset do release no GitHub.

```bash
# 4) Publique:
#    - anexe Lume-1.2.0.dmg como ASSET do release v1.2.0 no GitHub
#    - commite o appcast.xml na branch main (é o SUFeedURL)
git add appcast.xml && git commit -m "appcast v1.2.0" && git push
```

A partir daí, o app instalado verifica o `appcast.xml`, vê a versão nova, baixa o `.dmg`,
instala e reinicia — tudo pela UI padrão do Sparkle.

---

## Notas

- **Onde o app está instalado:** se estiver em `/Applications`, o Sparkle atualiza sem
  pedir senha. Em pastas protegidas, ele pede autorização.
- **Quarentena/Gatekeeper:** o Sparkle instala a versão baixada por ele mesmo (sem passar
  pelo "app baixado da internet"), então o relaunch ocorre sem o bloqueio típico de apps
  não assinados.
- **Versão (build):** o Sparkle compara o `CFBundleVersion` (build). Garanta que cada
  release **incremente o build** (`CURRENT_PROJECT_VERSION`) além do `MARKETING_VERSION`.
- O verificador antigo (GitHub API) foi **desativado** para não duplicar avisos; o
  `UpdateManager` permanece só para exibir a versão atual no About.
