<p align="center">
  <img src="Lume/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="Lume">
</p>

<h1 align="center">Lume</h1>

<p align="center">
  <strong>Native AI client for macOS</strong> — Chat, Cowork, and Code in a single app.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6.0-orange" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT">
</p>

---

## What's new in v1.4.0

The three modes are now genuinely distinct experiences, MCP is fully functional, RAG uses
contextual embeddings with on-disk caching, and the project moved to the Swift 6 language
mode. See [RELEASE_NOTES.md](RELEASE_NOTES.md) for the full list.

## Three modes, each purpose-built

Lume has one chat engine, but each mode exposes a different set of tools and a tailored
start screen, so the assistant behaves the way that context expects.

| Mode | What it's for | What the agent can do |
|---|---|---|
| **Chat** | A pure conversation: ask, write, brainstorm, translate. | Web search only — no file or shell access. |
| **Cowork** | Automating work over your files. | Read/write files, run code in a sandbox, use MCP connectors, create documents, track tasks. |
| **Code** | Agentic software engineering in a repository. | Shell, file editing, Git, plus everything above. The agent's command output appears in the conversation. |

Switching modes always returns to that mode's start screen, and the right-hand inspector
plus the capability strip above the input reflect the active mode.

## Key features

- **MCP (Model Context Protocol):** connect external tool servers over stdio or HTTP. Their
  tools are offered to the model in every provider, gated by an approval step. Connector
  status is shown in Settings → MCP and connectors auto-connect on launch.
- **RAG over your files:** documents are chunked and indexed with contextual embeddings
  (`NLContextualEmbedding`, multilingual and offline), with hybrid semantic + lexical
  retrieval and citations. The index is cached on disk and invalidated by content hash.
- **On-device AI (Apple Foundation Models):** context summarization and optional
  complexity-based model routing run locally — free, private, and offline — falling back to
  the API only when the local model isn't available.
- **Artifacts:** live preview of HTML / React / SVG / Mermaid in a split view, with version
  history to step back through revisions.
- **Multimodal & voice:** drag-and-drop / paste images, and native dictation via
  `SFSpeechRecognizer`.
- **Auto-update:** in-app updates via Sparkle (signed appcast, EdDSA).

## Supported providers

- **OpenAI** (GPT-4o, GPT-4-turbo, GPT-3.5-turbo, …)
- **Anthropic** (Claude Opus, Sonnet, Haiku)
- **OpenAI-compatible** endpoints (vLLM, TGI, Ollama, LiteLLM, Portkey, gateways, …)

## Installation

### Direct download

Download the latest `.dmg` from the [releases page](https://github.com/sbacaro/Lume/releases/latest).
After the first manual install, future updates are delivered automatically via Sparkle.

### Build from source

**Requirements:** macOS 14+ and Xcode 16+.

```bash
git clone https://github.com/sbacaro/Lume.git
cd Lume
open Lume.xcodeproj
```

Select the **Lume** scheme and press ⌘R to run, or ⌘U to run the test suite.

## How to use

1. Open **Settings → Providers** and add your API key.
2. Pick a mode with the switcher in the sidebar (or ⌘1 / ⌘2 / ⌘3):
   - **Chat** for general conversation and web-backed answers.
   - **Cowork** — create a project linked to a local folder; Lume indexes its files for RAG
     and can read, write, and organize them.
   - **Code** — point it at a repository; the agent runs shell commands, edits files, and
     works with Git.
3. Connect external tools in **Settings → MCP** to extend what the agent can do.

## Architecture

```
Lume/
├── Lume.xcodeproj/
└── Lume/
    ├── AIProviderManager.swift   # Orchestration: streaming, routing, context, tools
    ├── AnthropicProvider.swift / OpenAIProvider.swift  # Provider adapters
    ├── AgentTool*.swift          # Tool protocol, registry, and per-mode gating
    ├── MCPClient.swift           # MCP JSON-RPC client (stdio + HTTP)
    ├── RAGEngine.swift           # Indexing, retrieval, embeddings, on-disk cache
    ├── OnDeviceSummarizer.swift / OnDeviceComplexity.swift  # Foundation Models
    ├── LLMRouter.swift           # Complexity-based model routing
    ├── ChatDetailView.swift      # Chat surface + per-mode inspector
    └── ContentView.swift         # Navigation shell and the three modes
```

## Testing

The unit suite uses Swift Testing (`import Testing`) and covers the deterministic core —
routing, pricing, model capabilities, RAG scoring/persistence, MCP framing, JSON, and
artifact detection. Run it with ⌘U or:

```bash
xcodebuild test -scheme Lume -destination 'platform=macOS'
```

## Roadmap

- [ ] Computer Use mode (screen control via the Anthropic API)
- [ ] Native spreadsheets
- [x] Artifact version history
- [ ] Project export
- [ ] Custom color themes

## Contributing

Pull requests are welcome. For larger changes, please open an issue first to discuss what
you'd like to change.

## License

[MIT](LICENSE)

---

<p align="center">
  <strong>Made with ❤️ for the Mac.</strong>
</p>
