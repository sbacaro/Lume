# Atualização automática com Sparkle — Setup

O código já está integrado (`Lume/Updates/SparkleUpdater.swift`, menu **Verificar Atualizações…**,
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

## 4. Fluxo de cada release (depois do setup, é um comando)

Depois de concluir os passos 1–3 **uma vez**, cada release é só:

```bash
./release.sh            # ou ./release.sh 1.3.4 para bumpar a versão
```

O `release.sh` agora faz tudo, nesta ordem:

1. compila o app e gera o `Lume-<versão>.dmg` (com o `Lume.app` dentro);
2. se o Sparkle estiver instalado, **gera e assina o `appcast.xml`** (acha o
   `generate_appcast` no DerivedData, usa a chave privada do Keychain e aponta o
   download para o asset do release);
3. commita o que estiver pendente (incluindo o `appcast.xml`) e dá push na `main`
   — e a `main` é justamente o `SUFeedURL`;
4. cria a tag `vX.Y.Z` e o release no GitHub, **anexa o `.dmg`** e marca como *latest*.

A partir daí, o app instalado lê o `appcast.xml`, vê a versão nova, baixa o `.dmg`,
instala e reinicia — tudo pela UI padrão do Sparkle, sem navegador.

> Enquanto o Sparkle **não** estiver instalado, o `release.sh` apenas pula a etapa do
> appcast (sem quebrar) e avisa. A atualização automática só passa a valer depois do setup.

O `generate-appcast.sh` continua disponível para rodar a etapa do appcast isoladamente,
se você quiser.

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
