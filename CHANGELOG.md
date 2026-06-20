# Changelog — Lume

All notable changes to this project are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [1.4.2] — 2026-06-20

### Fixed

- **Responding glow follows the rounded corners**: the iridescent glow on the chat input is now drawn directly on the rounded field shape (`RoundedRectangle` `strokeBorder` for the crisp line + a blurred stroke of the same shape for the halo) instead of masking a pre-rendered square gradient image (`glowImage`/`ImageRenderer`), which produced a square-looking corner. The glow is animated by rotating the `AngularGradient` angle, so it stays light on the GPU (thin animated stroke, no per-frame full-area blur).
- **macOS "Support Ending for Intel-based Apps" warning**: the warning came from Lume launching an Intel-only CLI under Rosetta (the bundle itself, including Sparkle, is already universal). `Shell.fullPath` listed `/usr/local/bin` (legacy Intel Homebrew) before `/opt/homebrew/bin` (native arm64); on Apple silicon a leftover Intel tool there could shadow its arm64 build. `/opt/homebrew/bin:/opt/homebrew/sbin` now comes first, so native tools win and Lume stops spawning translated processes.
- **Swift 6 data race in the streaming pacer**: in `AIProviderManager.streamMessage`, the assistant `Message` (a non-`Sendable` SwiftData model) was captured and mutated by two concurrent tasks — the paced reveal loop and the network streaming task (`Sending 'assistantMsg' risks causing data races`). The pacer is now the sole owner of `assistantMsg` (it writes both the live text and the final `tokenCount`); the streaming task only fills the `@MainActor` `StreamReveal` buffer and updates conversation aggregates. Runtime behavior is unchanged.

---

## [1.4.1] — 2026-06-19

### Changed (UI)

- **Liquid Glass on the floating layer**: the chat input bar, sidebar controls, and the primary/secondary actions on each start screen now use macOS 26's `glassEffect` — translucent, light-refracting chrome floating above the content. Glass is applied only to the floating control layer, never to content panels, so text and lists stay crisp.
- **Apple-Intelligence-style glow while responding**: while the model is generating, the chat input field is wrapped in a soft, slowly rotating iridescent glow with a matching halo. It animates only during a response, then settles back to a clean hairline border so you always know where the input begins and ends.
- **One control language — pills everywhere**: every action button is now a rounded pill (capsule). The mix of square and rounded controls is gone, including the **Max tokens** selector in Providers, which is now a pill row. Segmented controls (Text size, Appearance) use a native-feeling pill segmented style.
- **Button colors**: primary actions use the accent color with white text; destructive actions follow the macOS standard (red text, not a heavy red fill).
- **Refined start screens**: each mode's capability list is now a centered two-column block under the title and actions, so Cowork and Code read as balanced layouts instead of left-shifted bullets.
- **Accent color** standardized on **#F09980** (the logo peach), tuned to sit well in both light and dark appearances.

### Added

- **Automatic CLI tool provisioning** (`install_tool`): a new agent tool installs a missing command-line tool via Homebrew during a task. On first use it bootstraps Homebrew at the standard prefix (`/opt/homebrew` on Apple Silicon) with a single native admin authentication — it creates and chowns the prefix via the macOS admin dialog, then downloads Homebrew as the user (no `sudo`/TTY, which is what makes the official installer fail inside a GUI app). `Shell.ensureHomebrew()`/`Shell.installFormula(_:)` back it; `run_shell`'s description now routes missing-tool cases here instead of manual curl/sudo. Available in Cowork and Code modes.

### Changed

- **Agent tool loop resets on progress instead of a hard cap**: `AnthropicProvider`/`OpenAIProvider` replaced the fixed `maxIterations = 20` (which ended the stream mid-task and required the user to type "continue") with an idle-rounds counter that resets whenever a round makes progress — a tool runs, or text/thinking is produced. Long multi-step tasks now run to the final answer; a `maxIdleRounds` watchdog plus an absolute `hardCap` still stop genuinely stuck loops.
- **Removed the streaming text cursor** (`▋`) that trailed the last block while a message streamed (`MarkdownParagraphView`/`MarkdownBulletView`).

### Added

- **Renderização suave (buffer + pacer)**: a resposta do modelo passa por um buffer (`StreamReveal`) — a rede preenche o texto recebido assim que chega e um laço separado (~25 fps) revela na tela numa cadência controlada (efeito máquina de escrever, com catch-up suave proporcional ao que falta). Desacopla a renderização das rajadas/pausas da rede (ferramenta, raciocínio), eliminando os saltos. O tok/s continua refletindo a chegada real; o texto completo é garantido ao final e em cancelamento.
- **Log de erros + erro copiável**: novo `ErrorLog` grava cada erro com timestamp em `Application Support/Lume/errors.log`. O toast de erro agora é selecionável, persiste até ser fechado (antes sumia em 6s, sem tempo de copiar) e tem botões **Copy** e **Open log** (revela o arquivo no Finder).

### Changed

- **Respostas extremamente lentas / "0 tok/s" (regressão de contexto)**: duas causas. (1) A compressão usava filtragem por similaridade semântica (`NLEmbedding` por mensagem) ao passar do orçamento — em conversas longas isso rodava embedding em todo o histórico a cada turno, travando antes do streaming (tempo-até-1º-token enorme). Trocado por corte por RECÊNCIA (barato); `filterByRelevance`/`semanticSimilarity` removidos (a relevância de documentos já vem do RAG). (2) O alvo de contexto era a janela inteira (ex.: ~178k), deixando o 1º token lento. Agora o alvo é MODERADO por padrão (~64k), honrando um cap maior configurado pelo usuário (`>= 32k`) e sempre limitado pela janela real. A proteção contra estouro continua via o trim no loop de ferramentas e o retry no erro de limite.
- **`temperature` rejeitada por modelo → re-tenta sem ela**: alguns endpoints (ex.: Claude via gateways OpenAI-compatible) respondem `400 "temperature is deprecated for this model"`. `AnthropicProvider`/`OpenAIProvider` detectam isso e re-tentam a chamada sem o parâmetro (via flag `allowTemperature`), em vez de falhar.

### Fixed

- **CPU alta / jank durante a resposta**: duas fontes. (1) A borda animada (glow) recalculava `AngularGradient` + `blur` a CADA frame (120Hz em ProMotion). Agora o gradiente é pré-renderizado UMA vez numa imagem já borrada (`ImageRenderer`) e a animação é só a rotação dessa imagem (transform barato, sem blur por frame). (2) Durante o streaming, a mensagem inteira era re-parseada em blocos de markdown (`parseBlocks` + `ForEach`) a cada atualização — O(n) por frame, saturando a CPU em respostas longas. Agora o texto em streaming é renderizado como um único `Text` simples; a formatação rica (títulos/código/listas) é aplicada uma vez ao finalizar.
- **Resposta presa no painel de raciocínio colapsado**: quando um modelo embrulhava a resposta num bloco `<think>` (ou nunca o fechava), `extractProcess` jogava tudo em eventos de raciocínio e deixava o `answer` vazio — a resposta só aparecia ao expandir o painel "Reasoning". Agora, com o stream encerrado, um `<think>` não fechado vira ANSWER; há rede de segurança que promove o raciocínio a resposta quando não sobra texto visível (e não há ferramentas); e tags `<think>`/`</think>` residuais são removidas do texto exibido. Durante o streaming o comportamento ao vivo ("Thinking…") é mantido.
- **Crash ao anexar imagem (Vision)**: os completion handlers de `VNRecognizeTextRequest`/`VNClassifyImageRequest` em `VisionOCR` eram inferidos como `@MainActor` (devido a `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), mas o Vision os invoca na própria fila — o runtime de concorrência abortava com `dispatch_assert_queue_fail`/`EXC_BREAKPOINT`. Removidos os completion handlers: `perform` roda na fila de fundo e `request.results` é lido ali mesmo (síncrono), sem closure isolada.
- **Context-window overflow (200k)**: long, tool-heavy turns no longer exceed the model's context limit. Four changes: (1) summarization of old history now runs for **all** providers, including custom/OpenAI-compatible (the `!isCustomProvider` guard was removed) and triggers against the real budget (`needsSummarization(budget:)`); (2) the history budget is sized off the model's real window minus system prompt + injected context (RAG/web/files, estimated from `finalContent` − `content`) + response reserve, respecting the user's configured cap when smaller; (3) `AnthropicProvider`/`OpenAIProvider` trim older `tool_result`/`tool` message contents (`trimMessagesToBudget`) before each loop request to stay under the window; (4) an over-limit HTTP error (400/413 mentioning context/token/maximum) triggers a tighter re-trim and retry instead of throwing. Also catalogued context windows for GLM (200k) and qwen/deepseek/mistral (128k) in `LLMRouter.maxContextWindow`.
- **Update checker stuck after dismiss**: `UpdateManager.checkForUpdates(force:)` now distinguishes an explicit user check (the About "Check" button → `checkForUpdatesForced()`) from an automatic one. A forced check ignores the 6h throttle **and** the previously dismissed version, and clears the dismissal — so the available version stops being suppressed forever after the sidebar notification was closed once. When no newer version exists, `availableRelease` is reset to `nil`.
- **Signed appcast (EdDSA)**: `release.sh` now guarantees `sparkle:edSignature` for the published DMG. `generate_appcast` does not re-sign an entry that already exists in the appcast (it only refreshes metadata), which had shipped an unsigned appcast and caused Sparkle to reject updates with "improperly signed and could not be validated." The script now signs the DMG with `sign_update` and injects the signature into the enclosure, and aborts if the app requires signing but no signature could be produced.

---

## [1.4.0] — 2026-06-18

### Changed (UI)

- **Per-mode start screen**: each mode now has its own start screen that explains what it does — Chat got a `ChatWelcomeView` (pure conversation + web search) in place of the generic launcher; Cowork emphasizes file automation; and Code fixed its description (the agent's command output appears in the conversation, no isolated terminal).
- **Per-mode chat (inspector + input)**: the right-hand panel now changes with the mode — Chat shows only Context/Notes; Cowork keeps Progress + project files; Code gains a "Repository" section with referenced files. Above the input, a strip indicates the mode and its real capabilities (Chat = web; Cowork = files/sandbox/MCP; Code = shell/Git/files), reflecting the tool gating.
- **Per-mode tools**: the set of tools exposed to the model now depends on the conversation's mode — **Chat** only searches the web (pure conversation, no file/shell access); **Cowork** has files, sandbox shell, web, and MCP (automation); **Code** has everything, including Git/GitHub. Previously, all tools were available in any mode. Applies to both Anthropic and OpenAI.
- **Code area cleanup**: removed the decorative Terminal, Code search, and Tests & Lint tools (the agent already runs shell/search/tests via tools, with output in the conversation). The Code sidebar became "Repository" with Git; MCP, redundant there, lives in Settings → MCP.
- **Terminal removed from chat**: the interactive terminal button/sheet was removed from `ChatDetailView` (Chat and Cowork) — Chat is pure conversation; in Code the "terminal" is the agent's command output.
- **Cowork**: removed the "Scheduled" item that had no action (scheduled tasks already appear in the Cowork dashboard).

### Added

- **Artifact version history**: when the agent revises an artifact (same type in the conversation), the previous content is preserved as a version. The artifact panel gained a navigator (◀ vN/M ▶) to view earlier versions in both the preview and the code, without losing the current one.
- **Persistent RAG index across sessions**: indexed embeddings are now cached on disk (Application Support/Lume/RAGIndex), one file per document, with invalidation by content hash (SHA-256) and backend/embedding-dimension identity. On relaunch, unchanged documents are loaded from cache instead of being re-embedded — no reprocessing every session. +2 tests.
- **Complexity-based model selection (on-device)**: a new optional toggle (off by default) "Auto-select model by complexity". When on, `LLMRouter` classifies the prompt's complexity with the on-device model (`OnDeviceComplexity`, Foundation Models) — with a heuristic fallback — and picks a cheaper or stronger model within the provider. Without the toggle, the chosen model stays sovereign (unchanged behavior). +2 tests.
- **On-device context summarization**: a new `OnDeviceSummarizer` (Apple Foundation Models, macOS 26+) summarizes old conversation history **locally** — free, offline, and private. `AIProviderManager` tries the on-device model first and only falls back to API summarization (which costs tokens) when the local model is unavailable. Reduces token usage in long conversations, with no regression.
- **Functional MCP (Model Context Protocol)**: a new `MCPClient` (actor) speaks JSON-RPC 2.0 over stdio with newline-delimited framing — `initialize`/`initialized` handshake, `tools/list`, and `tools/call`. Tools discovered from connected MCP servers enter `AgentToolExecutor.availableTools` (via `MCPAgentTool`) and are offered to the model across **all providers**, gated by approval. Settings → MCP has a **Connect / Refresh** button and a tool count. +15 tests (`MCPFramingTests`).

### Changed

- **Tool parity on OpenAI**: `OpenAIProvider.buildToolDefinitions()` is no longer a hardcoded list and now derives from `AgentToolExecutor.availableTools` (the same source as Anthropic) — GitHub and MCP tools now show up on OpenAI automatically.
- **RAG with contextual embeddings**: `TextEmbedder` rewritten as an `actor` using **`NLContextualEmbedding`** (a multilingual, contextual, native, offline transformer model; the Latin script covers PT+EN) with mean-pooling of token vectors, and a **fallback** to `NLEmbedding` (word2vec) when the model assets aren't present. The vector dimension is fixed on first load. Summary embeddings are now **cached in `index()`** (previously recomputed on every search). +11 tests (`RAGEngineTests`).
- **Real Swift 6**: the project migrated to **Swift 6 language mode** (`SWIFT_VERSION = 6.0`) with **strict concurrency `complete`** across all targets. The test target (Swift Testing) shares the app's `MainActor` isolation; `LumeUITests` (XCTest) stays nonisolated.

### Added

- **Test coverage** (Swift Testing): 48 tests covering `LLMRouter` (routing/heuristics), `ModelPricing` (cost/formatting), `ModelCapabilities` (vision), `ArtifactDetector` (markdown detection), and `JSONValue` (Codable/accessors/subscripts).

### Fixed

- **Concurrency under strict `complete`**: `WKNavigationDelegate.decisionHandler` marked `@MainActor` in `ArtifactPanelView` (the old signature "nearly matched" and the delegate might not even be called); `Task.detached` → `Task` in `ProjectDetailView` so non-`Sendable` `@Model` isn't sent across actors; `SpeechDelegateProxy.onEnd` is now `@Sendable`; `TaskScheduler` hops to the `MainActor` before `checkTasks()` in the `Timer` callback.
- **Dead code removed**: `SSEParser` (unreferenced; providers consume SSE directly via `URLSession.bytes`).

---

## [1.3.4] — 2026-06-16

### Added

- **Automatic updates via Sparkle**: when a new version is detected, the app downloads the `.dmg`, installs it, and relaunches on its own (standard Sparkle UI), **without opening the browser**. Secured by **EdDSA** signatures (signed appcast).
- **`setup-sparkle.sh`**: configures Sparkle end to end for everything automatable (resolves the package, generates the EdDSA keys, and injects the public key into the project).

### Changed

- **`release.sh`** now **generates and signs the appcast** automatically when Sparkle is installed, commits `appcast.xml`, and publishes the release with the **DMG** (the `Lume.app` ships inside the DMG). The PKG was discontinued.

---

## [1.3.3] — 2026-06-16

### Fixed

- **"Check for Updates…" menu** now checks **inside the app** and shows the status in the **About** window, instead of opening the releases page in the browser.
- **Tool-call rendering**: content with `]]`, `|`, or line breaks (e.g., a bash script with `if [[ … ]]`) no longer breaks the tool block. The payload is now **Base64**-encoded, so nothing leaks as raw text or shows literal `\n` in the bubble.

---

## [1.3.2] — 2026-06-16

### Fixed

- The **"Check"** (Check for updates) button on the **About** screen now checks **inside the app** and shows the status right there ("Checking…", "New version available: X", or "You're on the latest version."), instead of opening the releases page in the browser.

---

## [1.3.1] — 2026-06-16

### Added

- **Update notification in the sidebar**: a Lume-style popup (glass + brand gradient) appears **just above the model name**, at the bottom of the sidebar. Tap to update (via Sparkle); a button dismisses it.
- **Single source of truth for the version (`Version.xcconfig`)**: the version number now lives in a single file, from which the app, the About screen, and all scripts derive. Includes `set-version.sh` to bump in one command.

### Changed

- **`build-release.sh` is now a single self-contained file**: it compiles, builds the `.app`, and produces `Lume-<version>.dmg` (with the brand-gradient background and an Applications shortcut, headless) — the old `build-dmg.sh` was merged in.

### Fixed

- Build fix in the `SparkleUpdater` stub (missing `import Combine`), which prevented the build without the Sparkle package added.

---

## [1.3.0] — 2026-06-16

### Added

- **Automatic updates (Sparkle)**: the **Check for Updates…** menu and the About button download the `.dmg`, install it, and restart the app on their own — already on the new version at next launch. (Requires package and appcast setup — see `SETUP_SPARKLE.md`.)
- **Mode-aware AI**: the model now receives, at the top of the system prompt, a header stating whether it's in **Chat**, **Cowork**, or **Code**, with the role, tools, and expected behavior of each area.
- **Release scripts**:
  - `build-release.sh` — full pipeline: compiles, builds the `.app`, and delivers `Lume-<version>.dmg`.
  - `build-dmg.sh` — custom DMG with a **brand-gradient background**, arrow, and **Applications** shortcut, headless (no Finder dependency).
  - `generate-appcast.sh` — generates and signs (EdDSA) Sparkle's `appcast.xml`.

### Changed

- **Unified chat UI**: **Cowork** now uses the same composer (input box, model/approval menus, and bubbles) as Chat and Code — no more three different boxes.
- **More robust update checker**: fallback to the releases list when "latest" returns 404, a `User-Agent` header, and localized error messages.

### Fixed

- The **Code workspace context** no longer leaks into Chat conversations — it's restricted to Code mode.
- Task progress percentage formatted via **FormatStyle** (fixes the Xcode localization warning).
- Texts that still appeared in Portuguese are now localizable (e.g., "Verificar" → Check, "Modelo" → Model) and orphaned string-catalog keys were removed.

---

## [1.2.0] — 2026-06-16

### Added

#### Internationalization (i18n)
- **Full two-language support**: English (base) and **Portuguese (Brazil)**, with a string catalog (`Localizable.xcstrings`) covering the entire interface.
- **In-app language picker** in Settings → Advanced → **App Language**: choose between **System**, **English**, and **Português (Brasil)**, with automatic restart to apply.
- By default, the app now follows the macOS language (previously it was stuck in Portuguese).

### Changed

- **Buttons standardized to pill (capsule) shape** across the app — no more mixing of rounded and square corners; the Chat/Cowork/Code selector and the action buttons now share the same shape.
- Codebase migrated to **English as the source language**, with the Portuguese translations moved to the string catalog (instead of hardcoded text in the code).

### Fixed

- **AI key registered in onboarding** (and in the "Setup assistant") didn't appear in Settings, requiring re-registration — caused by the missing data context (`modelContext`) injection in the onboarding sheets.
- Various texts that were hardcoded in Portuguese and not going through translation are now localizable.

---

## [1.1.0] — 2026-06-15

### Added

#### About the app
- New professional **"About Lume"** screen, accessible from the menu (Lume → About Lume): app icon, version and build number, description, technical requirements, and copyright.
- Direct shortcuts to **GitHub repository**, **Release notes**, **Report an issue**, and **MIT License**.
- **Check for updates** button with live status, integrated with the release system.

#### Message rendering
- Markdown **tables** with a header, per-column alignment (`:--`, `--:`, `:-:`), zebra striping, and horizontal scroll.
- **Blockquotes** (`>`) with an accent bar.
- Task-list **checkboxes** (`- [ ]` / `- [x]`) with strikethrough text when completed.
- **Nested lists** with indentation and per-level markers (•/◦/▪).
- **Adjustable message font size** (Small/Default/Large/Extra) in Settings → Advanced, with a live preview.

#### Intelligence and context
- **Persistent memory** across conversations: user facts injected into the system prompt, with a management tab (categories, enable/disable, edit) and quick capture from any message.
- **Temporal context**: the current macOS date and time sent with each message, anchoring the AI in the present.
- **On-device conversation titles** via Apple Foundation Models (private, free, with fallback).
- **Hybrid RAG**: vector search (cosine) combined with lexical (BM25-lite).
- **Clickable RAG citations**: a "Sources" section in responses, with a popover for the snippet, document, and relevance.
- **Vision OCR**: text from attached images extracted locally (pt-BR/en) and included in the context — useful even for models without vision.
- **Model and cost badge**: the model chosen by automatic routing + tokens and estimated cost per conversation.

#### Interface and UX
- **Command palette (⌘K)** with global search by title *and* message content, and quick actions.
- **Keyboard shortcuts**: ⌘N (new conversation), ⌘F (search), ⌘1/2/3 (switch Chat/Cowork/Code).
- **Smart auto-scroll**: only follows the end if the user was already there, with a floating "go to bottom" button.
- **Transient error toast** (replaces error messages in the history).
- **Generation speed** (tok/s) live in the header during streaming.
- **Timestamp** also on assistant responses.
- **Thumbnails** of attached images, with individual removal.
- **Version history (branching)**: editing/restarting no longer destroys the previous segment — it's archived and can be reversibly restored.

#### Theme
- **Appearance** Light/Dark/System, applied across the app.

#### Voice
- **Text-to-speech (TTS)** of responses via `AVSpeechSynthesizer`, with markdown cleanup.
- Transcription abstraction (`TranscriptionProvider`) prepared for a local Whisper engine (WhisperKit).

#### Export
- Export a conversation as **Markdown** (file) and paginated **PDF**, plus copy to clipboard.

### Changed
- **Settings buttons standardized** into a single style system (primary, secondary, and destructive) with consistent shape, size, and states across all tabs and sheets.
- Code blocks now **auto-expand** when short (≤40 lines); long ones stay collapsed.
- Reading width of responses capped (~760pt) for legibility in wide windows.
- `RAGEngine` moved from purely vector search to **hybrid retrieval** with traceable sources.
- Automatic titles no longer use the first words of the text, switching to an on-device model.

### Removed
- **Custom accent color**: the option was removed from Settings; the app keeps only the appearance choice (Light/Dark/System).

### Fixed
- **Consistent dark theme**: the Chat mode start screen inherited a different background from the Cowork and Code screens; now they all use the same background color.
- **Concurrency (Swift 6)**: eliminated the warnings about mutating captured variables in `ShellFunctions`, wrapping the mutable state in a lock-protected reference type.
- Removed redundant `await`s on non-async calls (`AIProviderManager`, `AnthropicProvider`).

---

## [1.0.0] — 2025-06-26

### Added

#### Interface
- Sidebar with three modes: **Chat**, **Cowork**, and **Code**.
- Chat area with real-time token streaming.
- Xcode Dark–style syntax highlighting for Swift, Python, JS/TS, Bash, JSON, HTML, CSS, SQL, and Rust.
- Line numbers in code blocks.
- Diff viewer with colors for patch files.
- Code blocks collapsed by default, expandable on click.
- User messages with hover actions: send time, restart, edit, copy.
- AI messages with hover actions: copy, continue from here.
- Text selection spanning multiple messages.
- Update-available notification (animated card in the bottom-right corner).
- Active-model indicator in the sidebar's bottom bar.

#### Chat
- Support for multiple providers: **OpenAI**, **Anthropic**, custom providers (OpenAI-compatible).
- Per-provider model picker with dynamic models via API.
- Token streaming via Server-Sent Events (SSE).
- Semantic cache with disk persistence (24h TTL).
- Context compression using macOS-native NLEmbedding.
- Automatic summarization of long history.
- Automatic model routing by query complexity (inspired by RouteLLM).

#### Projects (Cowork)
- Creating projects from scratch with a local folder in `~/Lume/`.
- Importing existing conversations as projects.
- Importing existing folders.
- Per-project system prompt.
- File indexing for RAG (PDF, images, text, code).
- Right panel with instructions, context, and project files.

#### Agent tools
- Web search via DuckDuckGo (no API key).
- Web page fetch with text extraction.
- Shell command execution.
- File reading and writing.
- Directory listing and creation.
- Git integration (branch status, staged/modified files).

#### AI infrastructure
- Gateway compatible with LiteLLM, Portkey, Langfuse, vLLM, TGI, and Ollama.
- Native prompt caching (Anthropic `cache_control`, OpenAI seed).
- RAG Engine with NLEmbedding, hierarchical chunking, and similarity search.
- Agent orchestrator with a graph of steps, conditionals, and loops.
- Parallel subagent execution.

#### Voice
- Voice dictation using macOS-native `SFSpeechRecognizer`.
- Brazilian Portuguese recognition with English fallback.
- Visual recording indicator in the chat header.
- Automatic send after recording stops.

#### Multimodal
- Drag and drop images directly into the input field.
- Paste images from the clipboard (⌘V).
- Send images as base64 to compatible models (GPT-4o, Claude).

#### Artifacts
- Automatic detection of HTML, SVG, JavaScript, CSS, React, Mermaid, and Markdown.
- Interactive preview next to the chat.
- The inspector closes automatically when an artifact opens.

#### Updates
- Automatic update check via GitHub Releases (every 6 hours).
- Animated notification card with expandable release notes.
- Dismissed versions are remembered across sessions.

---

## Pending / Roadmap

- [ ] Computer Use mode (screen control via the Anthropic API)
- [ ] Native spreadsheets
- [x] Artifact version history
- [ ] Project export
- [ ] Local dictation with Whisper (WhisperKit) — abstraction ready, package still to be added in Xcode
- [x] Appearance modes (Light/Dark/System)
- [x] Persistent memory across conversations
- [x] Conversation version history (branching)
