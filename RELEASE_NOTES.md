# 🚀 Lume v1.4.0 — Real modes, MCP, smarter RAG, and on-device AI

Lume's biggest update yet. **Chat, Cowork, and Code** are now distinct experiences — each
with its own tools, start screen, and side panel. MCP works end to end, RAG gained
contextual embeddings with on-disk caching, and the codebase moved to Swift 6.

**Release date:** 2026-06-18
**Version:** v1.4.0 (build 12)
**Type:** Features

---

## ✨ Highlights

### Three modes, each purpose-built
- Tools are now scoped to the mode: **Chat** only searches the web (pure conversation),
  **Cowork** works on your files (read/write, sandbox, MCP), and **Code** has everything,
  including Git. The right-hand inspector and the capability strip above the input reflect
  the active mode.
- Each mode has its own start screen that explains what it does, and switching modes always
  returns to that start screen.
- Removed dead areas: the standalone Terminal / Search / Tests panels and the interactive
  terminal in chat. In Code, the agent's command output now appears right in the conversation.

### Functional MCP (Model Context Protocol)
- A JSON-RPC client over **stdio and HTTP**: handshake, `tools/list`, and `tools/call`.
  Tools from connected servers are offered to the agent in both providers (Anthropic and
  OpenAI), gated by approval, with per-connector status and auto-connect on launch.

### Smarter, persistent RAG
- **Contextual embeddings** (NLContextualEmbedding — multilingual and offline) replace
  word-vector averaging, with automatic fallback.
- The index is now **cached on disk**, so unchanged documents are not re-embedded on every
  launch.

### On-device AI (Apple Foundation Models)
- **Context summarization** and optional **complexity-based model routing** run on the local
  model — free, offline, and private — saving API tokens.

### Artifact version history
- Revised artifacts keep their previous versions; the artifact panel gained a navigator to
  step back and compare.

### Fixes & polish
- Fixed the in-app updater: the appcast feed URL is now provided via the Sparkle delegate,
  resolving the "must specify SUFeedURL" error.
- Each mode's start screen now shows the app version in the bottom-right corner.
- Switching modes always returns to that mode's start screen instead of keeping the previous
  conversation open.
- Inspector cleanup: removed a stray divider line, and the project files list now scrolls
  within a fixed height instead of truncating.

## 🔧 Quality
- Migrated to the **Swift 6 language mode** with strict concurrency set to `complete`, plus a
  suite of **~76 tests** covering routing, pricing, RAG, MCP, JSON, and artifact detection.

---

<details>
<summary>Histórico — versões anteriores</summary>

# ✨ Lume v1.3.4 — Atualização automática (Sparkle)

Esta versão liga a **atualização automática de verdade** via Sparkle: a partir dela, as
próximas versões baixam, instalam e reabrem o app sozinhas — **sem abrir o navegador**.

**Data de lançamento:** 2026-06-16
**Versão:** v1.3.4 (build 9)
**Tipo:** Funcionalidade

---

## ✨ Novidades

### Atualização automática via Sparkle
- Ao detectar uma versão nova, o app **baixa o `.dmg`, instala e reabre sozinho**, pela
  UI padrão do Sparkle — sem passar pelo navegador.
- Segurança por **assinatura EdDSA**: como o app é distribuído sem assinatura da Apple,
  o appcast assinado garante a integridade de cada atualização.

### Setup e release em um comando
- **`setup-sparkle.sh`** configura tudo que é automatizável: resolve o pacote, gera as
  chaves EdDSA e injeta a chave pública no projeto.
- **`release.sh`** passou a **gerar e assinar o appcast** automaticamente e publicar o
  release com o DMG (o `Lume.app` vai **dentro do DMG**).

---

## 🐞 Correções (incluídas da 1.3.3)

- **Menu "Check for Updates…"** verifica dentro do app (não abre mais o navegador).
- **Renderização de chamadas de ferramenta** corrigida (Base64): conteúdos com `]]`, `|`
  ou quebras de linha não vazam mais como texto cru nas mensagens.

---

> Importante: esta é a **primeira** build com Sparkle. Instale-a **manualmente** uma vez
> (a 1.3.2/1.3.3 não têm Sparkle para se auto-atualizar). Da próxima em diante, é automático.

<details>
<summary>Histórico — versões anteriores</summary>

# 🩹 Lume v1.3.3 — "Check for Updates" no menu e correção de renderização

Duas correções: o item **"Check for Updates…"** do menu passa a verificar **dentro do
app** (antes abria o navegador), e o conteúdo de chamadas de ferramenta não vaza mais
como texto cru nas mensagens.

**Data de lançamento:** 2026-06-16
**Versão:** v1.3.3 (build 8)
**Tipo:** Correções

---

## 🐞 Correções

- **Menu "Check for Updates…"** agora faz a verificação dentro do app e mostra o status
  na janela **Sobre** ("Procurando…", "Nova versão disponível: X" ou "Você está na versão
  mais recente."), em vez de abrir a página de releases do GitHub no navegador.
- **Renderização de chamadas de ferramenta corrigida**: scripts e conteúdos com `]]`, `|`
  ou quebras de linha (ex.: um script bash com `if [[ … ]]`) não quebram mais o bloco da
  ferramenta — o payload passou a ser codificado em Base64, então nada vaza como texto cru
  nem mostra `\n` literais na bolha.

---

<details>
<summary>Histórico — versões anteriores</summary>

# 🩹 Lume v1.3.2 — Correção do "Check" no About

Correção pontual: o botão de **verificar atualizações** na tela Sobre passa a checar
**dentro do app**, em vez de abrir o navegador.

**Data de lançamento:** 2026-06-16
**Versão:** v1.3.2 (build 7)
**Tipo:** Correção

---

## 🐞 Correções

- O botão **"Check"** na tela **Sobre** agora faz a verificação dentro do app e mostra o
  status ali mesmo ("Procurando…", "Nova versão disponível: X" ou "Você está na versão
  mais recente."), em vez de abrir a página de releases do GitHub no navegador.

---

<details>
<summary>Histórico — versões anteriores</summary>

# 🔔 Lume v1.3.1 — Notificação de atualização na sidebar e fonte única de versão

Esta versão traz um **popup de atualização no estilo do Lume** logo acima do nome do
modelo, uma **fonte única para o número da versão** e a consolidação do fluxo de release
em um único script.

**Data de lançamento:** 2026-06-16
**Versão:** v1.3.1 (build 6)
**Tipo:** Melhorias + correção

---

## ✨ Novidades

### Notificação de atualização na sidebar
- Quando há uma versão nova, aparece um **popup no estilo do Lume** (vidro + gradiente da
  marca) **logo acima do nome do modelo**, no rodapé da barra lateral. Toque para atualizar
  (via Sparkle); há um botão para dispensar.

### Fonte única da versão
- O número da versão agora vive só no **`Version.xcconfig`**. O app, o About e todos os
  scripts derivam dele. Use **`set-version.sh`** para bumpar em um comando.

---

## 🔧 Alterações

- **`build-release.sh` virou um único arquivo autocontido**: compila, gera o `.app` e
  produz o `Lume-<versão>.dmg` (fundo no gradiente da marca + atalho do Applications,
  headless). O antigo `build-dmg.sh` foi incorporado.

---

## 🐞 Correções

- Correção de compilação no stub do `SparkleUpdater` (faltava `import Combine`).

---

<details>
<summary>Histórico — versões anteriores</summary>

# 🧭 Lume v1.3.0 — Chat unificado, IA ciente do modo e auto-update

Esta versão **unifica a interface de chat** nos três modos, deixa o **modelo ciente de
onde está** (Chat, Cowork ou Code) e traz a base de **atualização automática (Sparkle)**
além de scripts de release com DMG personalizado.

**Data de lançamento:** 2026-06-16
**Versão:** v1.3.0 (build 5)
**Tipo:** Funcionalidades + correções

---

## ✨ Novidades

### Mesma UI de chat em todos os modos
- O **Cowork** passou a usar o **mesmo composer** (caixa de digitação, menus de modelo e
  aprovação, bolhas) do Chat e do Code. Acabaram as três caixas com aparências diferentes.

### IA ciente do modo
- O modelo recebe um cabeçalho dizendo se está em **Chat**, **Cowork** ou **Code**, com o
  papel, as ferramentas e o comportamento esperados de cada área — respostas mais alinhadas
  ao que cada modo faz.

### Atualização automática (Sparkle)
- **Verificar Atualizações…** (menu) e o botão no About baixam o `.dmg`, instalam e
  reiniciam o app sozinhos. Requer configuração — veja `SETUP_SPARKLE.md`.

### Scripts de release
- `build-release.sh` (compila → `.app` → `Lume-<versão>.dmg`), `build-dmg.sh` (DMG com
  fundo no gradiente da marca + atalho do Applications, headless) e `generate-appcast.sh`.

---

## 🔧 Alterações

- Verificador de atualizações mais robusto: fallback para a lista de releases, header
  `User-Agent` e mensagens de erro localizadas.

---

## 🐞 Correções

- O contexto do workspace de **Code** não vaza mais para conversas do **Chat**.
- Porcentagem do progresso de tarefas formatada via `FormatStyle` (corrige aviso do Xcode).
- Textos remanescentes em português agora localizáveis e chaves órfãs do catálogo removidas.

---

<details>
<summary>Histórico — versões anteriores</summary>

# 🌍 Lume v1.2.0 — Suporte a idiomas, botões em pílula e correções

Esta versão traz **internacionalização completa** (inglês + português do Brasil) com um
**seletor de idioma dentro do app**, a padronização de **todos os botões no formato pílula**
e a correção de um bug em que a chave de IA cadastrada no onboarding não aparecia em Configurações.

**Data de lançamento:** 2026-06-16
**Versão:** v1.2.0 (build 4)
**Tipo:** Funcionalidades + correções

---

## ✨ Novidades

### Dois idiomas, do seu jeito
- Interface disponível em **inglês** e **português (Brasil)**, cobrindo toda a aplicação
- Novo **seletor de idioma** em **Configurações → Avançado → Idioma do App**: escolha **Sistema**, **English** ou **Português (Brasil)**; o app reinicia para aplicar
- Por padrão, o Lume agora **segue o idioma do macOS** (antes ficava preso em português)

### Interface mais consistente
- **Todos os botões em formato pílula (cápsula)** — o seletor Chat/Cowork/Code, o botão "Add" e as ações de diálogos agora têm a mesma forma

---

## 🔧 Alterações

- Base de código migrada para **inglês como idioma de origem**; as traduções em português passam pelo catálogo de strings, e não mais por textos fixos no código

---

## 🐞 Correções

- **Chave de IA do onboarding** (e do "Setup assistant") não se refletia em Configurações, exigindo novo cadastro — corrigido ao injetar o contexto de dados correto nos sheets
- Diversos textos antes fixos em português agora são corretamente localizáveis

---

<details>
<summary>Histórico — v1.1.0 (2026-06-15)</summary>

# 🎉 Lume v1.1.0 — Tela "Sobre", interface consistente e correções

Esta versão traz uma nova tela **Sobre o Lume**, um sistema unificado de botões nas
Configurações, correções de consistência no tema escuro e a eliminação de avisos de
concorrência do Swift 6.

**Data de lançamento:** 2026-06-15
**Versão:** v1.1.0 (build 3)
**Tipo:** Funcionalidades + correções

---

## ✨ Novidades

### Tela "Sobre o Lume"
- Nova janela acessível pelo menu **Lume → Sobre o Lume**, no padrão de um app nativo do macOS
- Mostra o ícone do app, **versão e número de build**, descrição e requisitos técnicos
- Atalhos diretos para **Repositório no GitHub**, **Notas de versão**, **Reportar problema** e **Licença MIT**
- Botão **Verificar atualizações** com status ao vivo, integrado ao sistema de releases

### Interface mais consistente
- **Sistema único de botões** nas Configurações: estilos primário, secundário e destrutivo com a mesma forma, tamanho e comportamento em todas as abas e sheets — fim da mistura de cantos redondos/quadrados e tamanhos diferentes

---

## 🔧 Alterações

- A opção de **cor de acento** foi removida das Configurações; o app mantém apenas a escolha de **aparência** (Claro/Escuro/Sistema)

---

## 🐛 Correções

- **Tema escuro consistente:** a tela inicial do modo **Chat** herdava um fundo diferente do das telas **Cowork** e **Code**. Agora as três usam a mesma cor de fundo
- **Concorrência (Swift 6):** eliminados os avisos de mutação de variáveis capturadas em `ShellFunctions`, encapsulando o estado mutável num tipo de referência protegido por lock
- Removidos `await` redundantes em chamadas não-assíncronas (`AIProviderManager`, `AnthropicProvider`)

---

## 📦 Instalação

### Atualização automática
O app verifica novas versões pelo GitHub Releases. Quando houver atualização, basta
clicar em **Atualizar** na notificação (ou em **Verificar** na tela Sobre).

### Atualização manual
1. Baixe a versão mais recente em **GitHub Releases**
2. Arraste **Lume.app** para a pasta Aplicativos
3. Abra e aproveite

---

## 🖥️ Compatibilidade

- **macOS 14+** — binário universal (Intel / Apple Silicon)
- Totalmente retrocompatível com dados e configurações da v1.0.1

---

**Changelog completo:** veja [`CHANGELOG.md`](CHANGELOG.md) · [v1.1.0](https://github.com/sbacaro/Lume/releases/tag/v1.1.0)

</details>


</details>


</details>


</details>


</details>


</details>


</details>
