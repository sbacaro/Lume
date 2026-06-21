# 🔠 Lume v1.5.1 — Consistent typography & text zoom

This release unifies the app's typography and adds an accessibility text zoom, plus a tidier View menu.

**Release date:** 2026-06-21
**Version:** 1.5.1
**Type:** UI & accessibility

---

## 🆕 Added

### Text zoom (accessibility)
- New **View → Zoom In / Zoom Out / Actual Size** commands (**⌘+**, **⌘-**, **⌘0**) scale every text in the app from a single global factor (80%–160%), persisted across launches. Handy for readability and presentations.

## 🔄 Changed

### Unified typography system
- All text now flows through `LumeType`, a single source of truth for type. Roughly **570** hand-written `.font(.system(size:))` calls across the UI were migrated to a small set of semantic roles (`largeTitle`, `title1/2/3`, `body`, `callout`, `subheadline`, `footnote`, `caption`, `caption2`). Titles, body text, and captions are now consistent across panels — including the inspector, About, and Settings — and the right-hand inspector shares the same scale as the rest of the app.

### Tidier View menu
- Removed **Show Tab Bar** (window tabbing is disabled), **Show / Customize Toolbar**, and **Show Sidebar**, replacing them with the new Zoom commands.

---

# 🪪 Lume v1.5.0 — Now free software under the GNU GPLv3

Lume is relicensed from the MIT License to the **GNU General Public License v3.0**. This is a licensing change only — there are no changes to how the app behaves, looks, or performs.

**Release date:** 2026-06-21
**Version:** 1.5.0
**Type:** License change

---

## 🔄 Changed

### Relicensed from MIT to GNU GPLv3
- Lume is now **free software** under the [GNU General Public License v3.0](LICENSE). You are free to use, study, share, and modify it. Anyone who distributes Lume or a derivative work must do so under the same license and make the corresponding source available — keeping Lume and everything built on it open.
- Updated across the project: the `LICENSE` file (full GPLv3 text), the README badge and License section, the **About Lume** screen (license link and footer), and the localized UI strings (English + pt-BR).
- **No code behavior changes.** Existing features, performance, and on-disk data are unaffected by this release.

> Note: historical entries below that mention the MIT License describe the project as it was at the time of those earlier releases and are left unchanged as a record.

---

# 🚀 Lume v1.4.3 — Code highlights in Artifacts & Sandbox safety

This release introduces rich syntax highlighting and line numbers when inspecting Artifact source code directly in Lume, plus crash prevention fallbacks for system directory lookups and cleanup of obsolete files.

**Release date:** 2026-06-21
**Version:** 1.4.3
**Type:** Features & Stability

---

## 🎨 Added

### Syntax highlighting and line numbers in Artifact Code tab
- When opening the **Code** tab in an Artifact view, Lume now uses its high-performance token-caching `SyntaxHighlighter` to display beautifully styled source code for Swift, Python, JavaScript, CSS, HTML, SVG, and more, complete with a clean gutter showing line numbers.

## 🐞 Fixed

### Force-unwrap crash prevention on system directories
- Replaced all instances of `FileManager.default.urls(...).first!` with safe fallback wrappers. If the system fails to resolve default user directories (such as Application Support or Cache) due to sandbox or permission anomalies, Lume will fall back to using temporary paths instead of crashing immediately.

### Code cleanup
- Removed obsolete, unreferenced `ModelRouter.swift` and `SSEParser.swift` files from the disk and git.

---

# 🩹 Lume v1.4.2 — Rounded glow & Apple-silicon-friendly tooling

A small follow-up to 1.4.1 that fixes two rough edges: the responding glow on the chat
input now hugs the field's rounded corners instead of showing a square halo, and Lume
stops accidentally running Intel command-line tools under Rosetta — which was triggering
macOS's "Support Ending for Intel-based Apps" warning.

**Release date:** 2026-06-20
**Version:** 1.4.2.2
**Type:** Bug fixes

---

## 🐞 Fixed

### Responding glow now follows the rounded corners
- While the model is generating, the iridescent glow around the chat input is drawn
  directly on the rounded field shape (`strokeBorder` + a blurred halo on the same shape)
  instead of masking a pre-rendered square gradient image. The square-looking corner is
  gone — the glow and its halo now trace the field's rounded outline cleanly. It still
  animates only during a response and stays light on the GPU (a thin animated stroke, no
  per-frame full-area blur).

### No more "Support Ending for Intel-based Apps" warning from Lume
- The app bundle was already a universal binary (Intel + Apple silicon), including Sparkle.
  The warning came from Lume launching an **Intel-only command-line tool under Rosetta** —
  macOS attributes that to the app. Lume's shell `PATH` listed `/usr/local/bin` (the legacy
  Intel Homebrew location) **before** `/opt/homebrew/bin` (native arm64), so a leftover Intel
  tool could shadow its native build. On Apple silicon, `/opt/homebrew` now comes first, so
  native arm64 tools win and Lume stops spawning translated processes.
  - If you still see the warning, an Intel-only CLI is installed in `/usr/local/bin`;
    reinstall it as arm64 (e.g. `arch -arm64 brew reinstall <name>`).

### Build: data-race safety in the streaming pacer (Swift 6)
- Fixed a Swift 6 concurrency error in the response streamer: the assistant message (a
  SwiftData model, which isn't `Sendable`) was being written from two concurrent tasks — the
  paced reveal loop and the network streaming task. The paced loop is now the sole owner of
  that message (it writes the live text and the final token count), so the model object lives
  in a single isolation region. Runtime behavior is unchanged; the build is now clean under
  strict concurrency.

---

# ✨ Lume v1.4.1 — Liquid Glass, Intelligence glow, and a unified control language

A design-focused follow-up to 1.4.0. Lume's control layer now speaks Apple's **Liquid Glass**
(macOS 26), the chat input lights up with an **Apple-Intelligence-style glow** while the model
responds, and every button and toggle across the app finally follows one consistent pill style.

**Release date:** 2026-06-19
**Version:** 1.4.1.18
**Type:** Design & polish

---

## ✨ Highlights

### Liquid Glass on the floating layer
- The chat input bar, sidebar controls, and the primary/secondary actions on each start screen
  now use macOS 26's `glassEffect` — translucent, light-refracting chrome that floats above the
  content. Glass is applied only to the floating control layer, never to content panels, so
  text and lists stay crisp and readable.

### Apple-Intelligence-style glow while responding
- While the model is generating, the chat input field is wrapped in a soft, slowly rotating
  iridescent glow with a matching halo. It's lightweight and animates only during a response,
  then settles back to a clean hairline border so you always know where the input begins and ends.

### One control language: pills everywhere
- Every action button is now a rounded **pill** (capsule). The mix of square and rounded
  controls is gone — including the **Max tokens** selector in Providers, which is now a pill row.
- Primary actions use the accent color with white text; destructive actions follow the macOS
  standard (red text, not a heavy red fill).
- Segmented controls (Text size, Appearance) use a native-feeling pill segmented style.

### Refined start screens
- Each mode's capability list is now a centered two-column block under the title and actions,
  so Cowork and Code read as balanced, intentional layouts instead of left-shifted bullets.

### Accent color
- Standardized on **#F09980** (the logo peach) as the app accent, tuned to sit well in both
  light and dark appearances.

### Added
- **Smooth, paced rendering**: model output is now buffered and revealed on screen at a steady,
  controlled rate (a gentle typewriter effect) instead of in network-driven bursts — so replies
  flow smoothly even when tokens arrive in chunks or pause for a tool call. Generation speed
  (tok/s) still reflects the real arrival rate, and the full text is guaranteed at the end.
- **Installs missing command-line tools on its own**: when the agent needs a CLI that isn't on
  your Mac, Lume now installs it via Homebrew during the task — bootstrapping Homebrew itself on
  first use with a single native admin authentication (Touch ID / password), then `brew install`.
  No more dead ends when a tool like `radare2` or `ffmpeg` is missing.
- **Error log + copyable errors**: errors are saved to a log file and the error banner is now
  selectable, stays until you close it, and offers Copy and Open log buttons — so you can always
  capture what went wrong.

### Changed
- **Long tasks don't stop midway**: the agent's tool loop no longer hits a fixed ceiling that
  felt like a timeout and required typing "continue". The limit now resets on every step that
  makes progress (a tool runs, or text/thinking is produced), so multi-step work runs through to
  the final answer; a safety stop still catches genuinely stuck loops.
- Removed the blinking text cursor that trailed the response while streaming.
- **Faster responses on custom providers**: a context-budget regression made every turn run
  semantic filtering and an extra summarization call on conversations over ~12k tokens. The budget
  now uses the model's real window by default, so normal chats skip that work.

### Fixed
- **Works with models that reject `temperature`**: some endpoints (e.g. Claude via OpenAI-compatible
  gateways) return "`temperature` is deprecated for this model." Lume now retries without the
  parameter automatically instead of failing.
- **Smoother responses**: the animated glow around the input no longer drops frames while the
  model is replying — the effect is now rasterized into a single GPU layer instead of being
  recomposed every frame (noticeable on ProMotion displays).
- **Crash when attaching an image**: local image analysis (Vision OCR + classification) no longer
  crashes the app. The Vision completion handlers were being run off the main actor under strict
  concurrency; results are now read synchronously on a background queue instead.
- **Replies no longer hidden inside the collapsed reasoning panel**: if a model wrapped its actual
  answer in a `<think>` block (or never closed one), the response is now shown normally instead of
  being tucked away in the collapsed "Reasoning" panel — so you don't have to expand it to see what
  the model asked or said.
- **No more hard context-limit failures**: Lume now keeps the request within the model's real
  context window instead of letting a long, tool-heavy task overflow it (e.g. 200k). Conversation
  summarization runs for every provider — including custom/OpenAI-compatible ones like GLM, where
  it was previously skipped; the budget is sized off the real window minus the system prompt,
  injected context (RAG/web/files) and the response reserve; the agent loop trims older tool
  output as it approaches the limit; and an over-limit API error now triggers a tighter retry
  instead of failing.
- **Update check no longer gets stuck**: an explicit "Check" now always reveals a newer version
  and clears any previous "dismiss", instead of reporting "You're on the latest version" forever
  after the notification was closed once. Automatic checks still respect a dismissed version.
- **Signed auto-updates**: the appcast is now reliably signed (EdDSA), fixing the
  "improperly signed and could not be validated" error when installing an update via Sparkle.

---

# 🚀 Lume v1.4.0 — Real modes, MCP, smarter RAG, and on-device AI

Lume's biggest update yet. **Chat, Cowork, and Code** are now distinct experiences — each
with its own tools, start screen, and side panel. MCP works end to end, RAG gained
contextual embeddings with on-disk caching, and the codebase moved to Swift 6.

**Release date:** 2026-06-18
**Version:** 1.4.0.13
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

### Native UI overhaul (sidebars, inspector & start screens)
- Rebuilt all three sidebars (Chat / Cowork / Code) as native macOS lists — system fonts,
  sections, and labels — fully in English. Projects use a native disclosure group.
- The right-hand inspector now follows the same native list style.
- Each mode gets a redesigned, distinct start screen that reflects what it does: Chat shows
  suggestions, Cowork leads with "Create a project", and Code with "Open a repository"
  (adapting to the connected repo and its Git branch).
- Buttons are now consistent pills (capsules) across the app, and the app version is shown in
  the bottom-right of every start screen.
- Fixed: Chat start-screen suggestions now pre-fill the input instead of sending an
  incomplete message to the model.

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
