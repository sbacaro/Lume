<p align="center">
  <img src="Lume/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="Lume">
</p>

<h1 align="center">Lume</h1>

<p align="center">
  <strong>Native AI client for macOS</strong> — Chat, Cowork, and Code in a single app.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-26%2B-blue" alt="macOS 26+">
  <img src="https://img.shields.io/badge/Swift-6.0-orange" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/license-GPLv3-green" alt="GPLv3">
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PRs Welcome"></a>
  <a href="CODE_OF_CONDUCT.md"><img src="https://img.shields.io/badge/code%20of-conduct-ff69b4.svg" alt="Code of Conduct"></a>
</p>

---

## What's new in v1.5.1

Lume now has a unified typography system — titles, body text, and captions are consistent across every panel — plus an accessibility **text zoom** (View → Zoom In/Out, ⌘+ / ⌘- / ⌘0) and a tidier View menu. See [RELEASE_NOTES.md](RELEASE_NOTES.md) for details.

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

## Project structure

```
Lume/
├── Lume.xcodeproj/             # Xcode project (file-system synchronized groups)
├── Lume/                       # App source, grouped by responsibility
│   ├── App/                    # Entry point, root navigation, app config
│   ├── Models/                 # SwiftData @Model types and shared data structures
│   ├── AI/                     # The chat engine
│   │   ├── Providers/          #   OpenAI / Anthropic / gateway adapters + manager
│   │   ├── Routing/            #   Complexity-based model routing, pricing, capabilities
│   │   ├── Context/            #   Context window management, compression, caches
│   │   └── OnDevice/           #   Apple Foundation Models (summary, complexity, titles)
│   ├── RAG/                    # File indexing, retrieval, contextual embeddings
│   ├── MCP/                    # Model Context Protocol client + connector
│   ├── Agent/                  # Tool protocol, executor, orchestration
│   │   └── Tools/              #   Built-in tools (web fetch/search, GitHub)
│   ├── Services/               # Infra: Keychain, Git, shell, terminal, memory, OCR…
│   ├── Updates/                # Sparkle + in-app self-updater
│   ├── DesignSystem/           # Brand, theme, button styles, app-icon rendering
│   ├── Views/                  # SwiftUI surfaces
│   │   ├── Chat/  Settings/  Onboarding/  Markdown/  Components/
│   │   └── …                   #   Dashboards, project sheets, terminal
│   ├── Assets.xcassets/        # Asset catalog
│   └── Lume.entitlements       # Sandbox/runtime entitlements
├── LumeTests/                  # Unit tests (Swift Testing)
├── LumeUITests/                # UI tests
├── docs/                       # Architecture & setup guides
├── scripts/                    # release.sh, set-version.sh, setup-sparkle.sh
├── Version.xcconfig            # Single source of truth for version + build
├── appcast.xml                 # Sparkle update feed
├── Localizable.xcstrings       # Localization (English + pt-BR)
└── LICENSE  README.md  CHANGELOG.md  RELEASE_NOTES.md  CONTRIBUTING.md …
```

A deeper component-level walkthrough lives in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

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

[GNU General Public License v3.0](LICENSE)

Lume is free software: you can redistribute it and/or modify it under the terms of the GNU
General Public License as published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version. Lume is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  <strong>Made with ❤️ for the Mac.</strong>
</p>
